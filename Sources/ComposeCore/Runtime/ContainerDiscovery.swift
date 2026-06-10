import ContainerAPIClient
import ContainerResource
import Foundation

public struct DiscoveredContainer: Sendable, Equatable {
    /// Container name as used by the `container` CLI (`--name` / snapshot id).
    public let name: String
    /// Compose service name from `com.docker.compose.service`, when present.
    public let serviceName: String?

    public init(name: String, serviceName: String? = nil) {
        self.name = name
        self.serviceName = serviceName
    }
}

public struct ProjectContainer: Sendable {
    public let name: String
    public let serviceName: String?
    public let status: RuntimeStatus
    public let publishedPorts: [PublishPort]

    public init(
        name: String,
        serviceName: String?,
        status: RuntimeStatus,
        publishedPorts: [PublishPort]
    ) {
        self.name = name
        self.serviceName = serviceName
        self.status = status
        self.publishedPorts = publishedPorts
    }
}

public enum ContainerDiscovery {
    public static func containers(forProject projectName: String) async throws -> [DiscoveredContainer] {
        try await projectContainers(forProject: projectName).map {
            DiscoveredContainer(name: $0.name, serviceName: $0.serviceName)
        }
    }

    public static func projectContainers(forProject projectName: String) async throws -> [ProjectContainer] {
        let client = ContainerClient()
        let snapshots = try await client.list(filters: listFilters(forProject: projectName))
        return snapshots
            .map { snapshot in
                ProjectContainer(
                    name: snapshot.id,
                    serviceName: snapshot.configuration.labels[ComposeLabels.service],
                    status: snapshot.status,
                    publishedPorts: snapshot.configuration.publishedPorts
                )
            }
            .sorted { $0.name < $1.name }
    }

    private static func listFilters(forProject projectName: String) -> ContainerListFilters {
        ContainerListFilters(
            labels: [ComposeLabels.project: exactMatchRegex(projectName)]
        ).withoutMachines()
    }

    private static func exactMatchRegex(_ value: String) -> String {
        "^\(NSRegularExpression.escapedPattern(for: value))$"
    }
}
