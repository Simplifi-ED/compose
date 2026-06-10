import ContainerAPIClient
import ContainerResource
import Foundation

public struct DiscoveredContainer: Sendable, Equatable {
    /// Container name as used by the `container` CLI (`--name` / snapshot id).
    public let name: String

    public init(name: String) {
        self.name = name
    }
}

public enum ContainerDiscovery {
    public static func containers(forProject projectName: String) async throws -> [DiscoveredContainer] {
        let client = ContainerClient()
        let snapshots = try await client.list(filters: listFilters(forProject: projectName))
        return snapshots
            .map { DiscoveredContainer(name: $0.id) }
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
