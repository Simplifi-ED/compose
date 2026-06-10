import ContainerAPIClient
import ContainerResource
import Foundation

public struct DiscoveredContainer: Sendable, Equatable {
    public let name: String
    public let service: String

    public init(name: String, service: String) {
        self.name = name
        self.service = service
    }
}

public enum ContainerDiscovery {
    public static func listFilters(forProject projectName: String) -> ContainerListFilters {
        ContainerListFilters(
            labels: [ComposeLabels.project: ComposeLabels.exactMatchRegex(projectName)]
        ).withoutMachines()
    }

    public static func containers(forProject projectName: String) async throws -> [DiscoveredContainer] {
        let client = ContainerClient()
        let snapshots = try await client.list(filters: listFilters(forProject: projectName))
        return snapshots
            .map { snapshot in
                DiscoveredContainer(
                    name: snapshot.id,
                    service: snapshot.configuration.labels[ComposeLabels.service]
                        .flatMap { $0.isEmpty ? nil : $0 } ?? snapshot.id
                )
            }
            .sorted { $0.name < $1.name }
    }
}
