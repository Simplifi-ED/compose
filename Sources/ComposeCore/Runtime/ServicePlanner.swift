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
        try composeFile.services
            .sorted { $0.key < $1.key }
            .map { serviceName, service in
                try plan(
                    serviceName: serviceName,
                    service: service,
                    projectName: projectName,
                    composeDirectory: composeDirectory
                )
            }
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
