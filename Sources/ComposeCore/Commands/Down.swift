import ArgumentParser
import Foundation

public struct Down: AsyncParsableCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        abstract: "Stop and remove containers for the compose project."
    )

    @OptionGroup
    var projectOptions: ProjectOptions

    public func run() async throws {
        let fileURL = projectOptions.resolvedFileURLIfPresent()
        let projectName = try projectOptions.resolvedProjectName(fileURL: fileURL)
        let containers = try await ContainerDiscovery.containers(forProject: projectName)

        if let fileURL {
            let composeFile = try ComposeParser.parseForShutdown(fileURL: fileURL)
            let shutdown = try ServicePlanner.shutdownContainerLayers(
                for: composeFile,
                containers: containers
            )
            if !shutdown.orphans.isEmpty {
                let names = shutdown.orphans.map(\.name).joined(separator: ", ")
                fputs(
                    """
                    Warning: \(shutdown.orphans.count) container(s) without a compose service mapping (\(names)) \
                    stop last; depends_on order may not apply to them.\n
                    """,
                    stderr
                )
            }
            try await ServiceRunner.down(layers: shutdown.layers)
        } else {
            try await ServiceRunner.down(containers: containers)
        }

        for container in containers {
            print(container.name)
        }
    }
}
