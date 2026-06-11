import Foundation

enum ServiceRunMapping {
    static func appendServiceRunConfiguration(
        to arguments: inout [String],
        serviceName: String,
        service: ComposeService,
        projectName: String,
        composeDirectory: URL,
        image: String,
        command: [String],
        containerNumber: Int = 1
    ) throws {
        arguments.append(contentsOf: ComposeLabels.runFlags(
            projectName: projectName,
            serviceName: serviceName,
            containerNumber: containerNumber
        ))
        arguments.append(contentsOf: environmentFlags(service.environment))
        for port in service.ports {
            if let flag = try publishFlag(for: port) {
                arguments.append(contentsOf: ["-p", flag])
            }
        }
        for volume in service.volumes {
            arguments.append(contentsOf: ["-v", try volumeFlag(for: volume, relativeTo: composeDirectory)])
        }
        arguments.append(image)
        arguments.append(contentsOf: command)
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

    /// Publish flag for a port spec, or `nil` for container-only specs
    /// (the runtime can't allocate dynamic host ports, so no host bind is made).
    static func publishFlag(for port: String) throws -> String? {
        guard let spec = ComposeBindingKeys.parsePortSpec(port) else {
            throw ComposeError.unsupportedPort(port)
        }
        guard let hostPort = spec.hostPort else {
            return nil
        }

        if spec.protocolSuffix.isEmpty {
            return "127.0.0.1:\(hostPort):\(spec.containerPort)"
        }
        return "127.0.0.1:\(hostPort):\(spec.containerPort)\(spec.protocolSuffix)"
    }

    static func volumeFlag(for volume: String, relativeTo composeDirectory: URL) throws -> String {
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
            let standardized = resolvedHostURL.standardizedFileURL.resolvingSymlinksInPath()
            let composeRoot = composeDirectory.standardizedFileURL.resolvingSymlinksInPath()
            guard isPathContained(standardized, within: composeRoot) else {
                throw ComposeError.invalidField(
                    "volumes",
                    reason: "host path '\(hostPath)' resolves outside the compose file directory. "
                        + "Use a path within the project or an absolute host path."
                )
            }
        }
        let absoluteHostPath = resolvedHostURL.standardizedFileURL.path

        guard FileManager.default.fileExists(atPath: absoluteHostPath) else {
            throw ComposeError.volumeHostPathNotFound(path: absoluteHostPath)
        }

        return "\(absoluteHostPath):\(containerPath)"
    }

    private static func isPathContained(_ path: URL, within root: URL) -> Bool {
        let resolvedPath = path.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        if resolvedPath == rootPath {
            return true
        }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return resolvedPath.hasPrefix(prefix)
    }
}
