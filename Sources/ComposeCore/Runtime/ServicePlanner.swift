import Foundation

public struct ServicePlan: Sendable, Equatable {
    public let serviceName: String
    public let containerID: String
    public let runArguments: [String]
}

public enum ServicePlanner {
    public static func plans(for composeFile: ComposeFile, projectName: String) throws -> [ServicePlan] {
        try composeFile.services
            .sorted { $0.key < $1.key }
            .map { serviceName, service in
                try plan(
                    serviceName: serviceName,
                    service: service,
                    projectName: projectName
                )
            }
    }

    public static func containerID(
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
        projectName: String
    ) throws -> ServicePlan {
        guard let image = service.image, !image.isEmpty else {
            throw ComposeError.missingImage(service: serviceName)
        }

        let containerID = containerID(
            serviceName: serviceName,
            service: service,
            projectName: projectName
        )

        var arguments = ["-d", "--name", containerID]
        arguments.append(contentsOf: environmentFlags(service.environment))
        for port in service.ports {
            arguments.append(contentsOf: ["-p", try publishFlag(for: port)])
        }
        arguments.append(image)
        arguments.append(contentsOf: commandArguments(service.command))

        return ServicePlan(
            serviceName: serviceName,
            containerID: containerID,
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
}
