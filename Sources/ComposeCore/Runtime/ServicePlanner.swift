import Foundation

public struct ServicePlan: Sendable, Equatable {
    public let serviceName: String
    public let name: String
    public let runArguments: [String]
}

public enum ServicePlanner {
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
        var inDegree: [String: Int] = [:]
        var dependents: [String: [String]] = [:]

        for serviceName in services.keys {
            inDegree[serviceName] = 0
            dependents[serviceName] = []
        }

        for (serviceName, service) in services {
            var seenDependencies: Set<String> = []
            let dependencies = service.dependsOn.filter { seenDependencies.insert($0).inserted }
            inDegree[serviceName] = dependencies.count
            for dependency in dependencies {
                guard services.keys.contains(dependency) else {
                    throw ComposeError.unknownDependency(service: serviceName, dependency: dependency)
                }
                dependents[dependency, default: []].append(serviceName)
            }
        }

        var layers: [[(serviceName: String, service: ComposeService)]] = []
        var remaining = services.count

        while remaining > 0 {
            let layer = inDegree
                .filter { $0.value == 0 }
                .map(\.key)
                .sorted()

            guard !layer.isEmpty else {
                throw ComposeError.circularDependency(services: findCycle(in: services))
            }

            layers.append(layer.map { ($0, services[$0]!) })
            remaining -= layer.count

            for serviceName in layer {
                inDegree.removeValue(forKey: serviceName)
                for dependent in dependents[serviceName, default: []] {
                    inDegree[dependent, default: 0] -= 1
                }
            }
        }

        return layers
    }

    private static func findCycle(in services: [String: ComposeService]) -> [String] {
        var visited: Set<String> = []
        var stack: Set<String> = []
        var path: [String] = []

        func dfs(_ serviceName: String) -> [String]? {
            if stack.contains(serviceName) {
                if let start = path.firstIndex(of: serviceName) {
                    return Array(path[start...]) + [serviceName]
                }
                return [serviceName, serviceName]
            }
            if visited.contains(serviceName) {
                return nil
            }

            visited.insert(serviceName)
            stack.insert(serviceName)
            path.append(serviceName)

            for dependency in services[serviceName]?.dependsOn ?? [] {
                if let cycle = dfs(dependency) {
                    return cycle
                }
            }

            path.removeLast()
            stack.remove(serviceName)
            return nil
        }

        for serviceName in services.keys.sorted() {
            if let cycle = dfs(serviceName) {
                return cycle
            }
        }

        return Array(services.keys.sorted())
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
        let trimmed = port.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ComposeError.unsupportedPort(port)
        }

        let protocolSuffix: String
        let hostContainerPart: String
        if let slashIndex = trimmed.firstIndex(of: "/") {
            hostContainerPart = String(trimmed[..<slashIndex])
            protocolSuffix = String(trimmed[slashIndex...])
        } else {
            hostContainerPart = trimmed
            protocolSuffix = ""
        }

        let parts = hostContainerPart.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              Int(parts[0]) != nil,
              Int(parts[1]) != nil
        else {
            throw ComposeError.unsupportedPort(port)
        }

        if protocolSuffix.isEmpty {
            return "127.0.0.1:\(hostContainerPart)"
        }
        return "127.0.0.1:\(hostContainerPart)\(protocolSuffix)"
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
