import Foundation

struct ServiceRunConfiguration: Sendable {
    let serviceName: String
    let service: ComposeService
    let projectName: String
    let composeDirectory: URL
    let image: String
    let command: [String]
    var containerNumber: Int = 1
    var machineName: String?
    var requireAgentReachability: Bool = true
}

enum ServiceRunMapping {
    static func appendServiceRunConfiguration(
        to arguments: inout [String],
        configuration: ServiceRunConfiguration
    ) throws {
        arguments.append(contentsOf: ComposeLabels.runFlags(
            projectName: configuration.projectName,
            serviceName: configuration.serviceName,
            containerNumber: configuration.containerNumber,
            machineName: configuration.machineName
        ))
        arguments.append(contentsOf: environmentFlags(configuration.service.environment))
        for port in configuration.service.ports {
            if let flag = try publishFlag(for: port) {
                arguments.append(contentsOf: ["-p", flag])
            }
        }
        for volume in configuration.service.volumes {
            arguments.append(contentsOf: [
                "-v",
                try volumeFlag(
                    for: volume,
                    relativeTo: configuration.composeDirectory,
                    projectName: configuration.projectName
                )
            ])
        }
        arguments.append(contentsOf: try SSHAgentForwarding.runFlags(
            service: configuration.service,
            serviceName: configuration.serviceName,
            requireAgentReachability: configuration.requireAgentReachability
        ))
        arguments.append(contentsOf: try NetworkPlanning.networkFlags(
            service: configuration.service,
            projectName: configuration.projectName
        ))
        if configuration.service.useInit == true {
            arguments.append("--init")
        }
        try DeployGPUPlanning.validateReservations(
            configuration.service.deploy?.resources?.reservations,
            machineName: configuration.machineName
        )
        arguments.append(contentsOf: try DeployResourceLimitsPlanning.validatedRunFlags(
            limits: configuration.service.deploy?.resources?.limits
        ))
        arguments.append(contentsOf: try PlatformPlanning.validatedRunFlags(
            platform: configuration.service.platform
        ))
        arguments.append(configuration.image)
        arguments.append(contentsOf: configuration.command)
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

    static func volumeFlag(
        for volume: String,
        relativeTo composeDirectory: URL,
        projectName: String
    ) throws -> String {
        let spec = try ComposeBindingKeys.parseVolumeSpec(volume)
        switch spec.source {
        case .named(let logicalName):
            let runtimeName = try VolumePlanning.runtimeVolumeName(
                projectName: projectName,
                volumeName: logicalName
            )
            return spec.formattedMount(mountSource: runtimeName)
        case .bindMount(let hostPath):
            let resolvedHostURL: URL
            switch try BindMountPathResolver.resolveHostPath(hostPath, relativeTo: composeDirectory) {
            case .projectRelative(let url), .absoluteExternal(let url):
                resolvedHostURL = url
            }
            let absoluteHostPath = resolvedHostURL.path

            guard FileManager.default.fileExists(atPath: absoluteHostPath) else {
                throw ComposeError.volumeHostPathNotFound(path: absoluteHostPath)
            }

            return spec.formattedMount(mountSource: absoluteHostPath)
        }
    }
}
