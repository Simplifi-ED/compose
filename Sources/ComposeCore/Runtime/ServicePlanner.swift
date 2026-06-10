import Foundation

public struct ServicePlan: Sendable, Equatable {
    public let serviceName: String
    public let name: String
    public let runArguments: [String]
}

public enum ServicePlanner {
    public static func plans(
        for composeFile: ComposeFile,
        projectName: String,
        composeDirectory: URL
    ) throws -> [ServicePlan] {
        try startupLayers(
            for: composeFile,
            projectName: projectName,
            composeDirectory: composeDirectory
        ).flatMap { $0 }
    }

    public static func startupLayers(
        for composeFile: ComposeFile,
        projectName: String,
        composeDirectory: URL
    ) throws -> [[ServicePlan]] {
        try dependencyLayers(for: composeFile).map { layer in
            try layer.map { serviceName, service in
                try plan(
                    serviceName: serviceName,
                    service: service,
                    projectName: projectName,
                    composeDirectory: composeDirectory
                )
            }
        }
    }

    static func dependencyLayers(
        for composeFile: ComposeFile
    ) throws -> [[(serviceName: String, service: ComposeService)]] {
        let services = composeFile.services
        return try DependencyGraph.serviceLayers(for: services).map { layer in
            layer.map { ($0, services[$0]!) }
        }
    }

    static func shutdownLayers(
        for composeFile: ComposeFile,
        discoveredServiceNames: Set<String>
    ) throws -> [[String]] {
        try DependencyGraph.serviceLayers(for: composeFile.services)
            .reversed()
            .map { layer in layer.filter { discoveredServiceNames.contains($0) } }
            .filter { !$0.isEmpty }
    }

    public static func shutdownContainerLayers(
        for composeFile: ComposeFile,
        containers: [DiscoveredContainer]
    ) throws -> [[DiscoveredContainer]] {
        let byService = Dictionary(grouping: containers.compactMap { container -> (String, DiscoveredContainer)? in
            guard let serviceName = container.serviceName else { return nil }
            return (serviceName, container)
        }) { $0.0 }
            .mapValues { pairs in pairs.map(\.1) }
        let discoveredServiceNames = Set(byService.keys)
        let serviceLayers = try shutdownLayers(
            for: composeFile,
            discoveredServiceNames: discoveredServiceNames
        )

        var layers = serviceLayers.map { layer in
            layer.flatMap { byService[$0, default: []] }
        }

        let orphans = unmappedContainers(in: containers, composeFile: composeFile)
        if !orphans.isEmpty {
            layers.append(orphans)
        }

        return layers
    }

    static func unmappedContainers(
        in containers: [DiscoveredContainer],
        composeFile: ComposeFile
    ) -> [DiscoveredContainer] {
        let knownServices = Set(composeFile.services.keys)
        return containers.filter { container in
            guard let serviceName = container.serviceName else { return true }
            return !knownServices.contains(serviceName)
        }
        .sorted { $0.name < $1.name }
    }

    public static func containerName(
        serviceName: String,
        service: ComposeService,
        projectName: String
    ) -> String {
        if let containerName = service.containerName, !containerName.isEmpty {
            return containerName
        }
        return "\(projectName)_\(serviceName)"
    }

    public static func plan(
        serviceName: String,
        service: ComposeService,
        projectName: String,
        composeDirectory: URL
    ) throws -> ServicePlan {
        guard let image = service.image, !image.isEmpty else {
            throw ComposeError.missingImage(service: serviceName)
        }

        let name = containerName(
            serviceName: serviceName,
            service: service,
            projectName: projectName
        )

        var arguments = ["-d", "--name", name]
        arguments.append(contentsOf: ComposeLabels.runFlags(projectName: projectName, serviceName: serviceName))
        arguments.append(contentsOf: environmentFlags(service.environment))
        for port in service.ports {
            arguments.append(contentsOf: ["-p", try publishFlag(for: port)])
        }
        for volume in service.volumes {
            arguments.append(contentsOf: ["-v", try volumeFlag(for: volume, relativeTo: composeDirectory)])
        }
        arguments.append(image)
        arguments.append(contentsOf: commandArguments(service.command))

        return ServicePlan(
            serviceName: serviceName,
            name: name,
            runArguments: arguments
        )
    }

    static func environmentFlags(_ environment: ComposeEnvironment?) -> [String] {
        guard let environment else { return [] }
        switch environment {
        case .map(let values):
            return values.flatMap { key, value in ["-e", "\(key)=\(value)"] }
        case .list(let values):
            return values.flatMap { ["-e", $0] }
        }
    }

    static func commandArguments(_ command: ComposeCommandValue?) -> [String] {
        guard let command else { return [] }
        switch command {
        case .string(let value):
            return value.split(whereSeparator: \.isWhitespace).map(String.init)
        case .list(let values):
            return values
        }
    }

    public static func publishFlag(for port: String) throws -> String {
        guard let spec = ComposeBindingKeys.parsePortSpec(port) else {
            throw ComposeError.unsupportedPort(port)
        }

        if spec.protocolSuffix.isEmpty {
            return "127.0.0.1:\(spec.hostPort):\(spec.containerPort)"
        }
        return "127.0.0.1:\(spec.hostPort):\(spec.containerPort)\(spec.protocolSuffix)"
    }

    public static func volumeFlag(for volume: String, relativeTo composeDirectory: URL) throws -> String {
        let trimmed = volume.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ComposeError.unsupportedVolume(volume)
        }

        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count == 3 {
            throw ComposeError.unsupportedVolumeOption(volume)
        }
        guard parts.count == 2 else {
            throw ComposeError.unsupportedVolume(volume)
        }

        let hostPath = String(parts[0])
        let containerPath = String(parts[1])

        guard !hostPath.isEmpty, !containerPath.isEmpty else {
            throw ComposeError.unsupportedVolume(volume)
        }
        guard containerPath.hasPrefix("/") else {
            throw ComposeError.unsupportedVolume(volume)
        }

        let isBindMountSource = hostPath.contains("/") || hostPath == "." || hostPath == ".."
        guard isBindMountSource else {
            throw ComposeError.unsupportedNamedVolume(volume)
        }

        let resolvedHostURL: URL
        if hostPath.hasPrefix("/") {
            resolvedHostURL = URL(fileURLWithPath: hostPath)
        } else {
            resolvedHostURL = composeDirectory.appendingPathComponent(hostPath)
        }
        let absoluteHostPath = resolvedHostURL.standardizedFileURL.path

        guard FileManager.default.fileExists(atPath: absoluteHostPath) else {
            throw ComposeError.volumeHostPathNotFound(path: absoluteHostPath)
        }

        return "\(absoluteHostPath):\(containerPath)"
    }
}
