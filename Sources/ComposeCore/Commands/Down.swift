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
        let fileURL = try projectOptions.resolvedFileURLIfPresent()
        let projectName = try projectOptions.resolvedProjectName(fileURL: fileURL)
        let containers = try await ContainerDiscovery.containers(forProject: projectName)

        let useOrderedShutdown = fileURL != nil && !projectOptions.hasExplicitProjectName

        if useOrderedShutdown, let fileURL {
            let composeFile = try ComposeParser.parseForShutdown(fileURL: fileURL)
            let layers = try ServicePlanner.shutdownContainerLayers(
                for: composeFile,
                containers: containers
            )
            let unmapped = ServicePlanner.unmappedContainers(in: containers, composeFile: composeFile)
            if !unmapped.isEmpty {
                let names = unmapped.map(\.name).joined(separator: ", ")
                fputs(
                    """
                    Warning: \(unmapped.count) container(s) without a compose service mapping (\(names)) \
                    stop last; depends_on order may not apply to them.\n
                    """,
                    stderr
                )
            }
            try await ServiceRunner.down(layers: layers) { print($0) }
        } else {
            try await ServiceRunner.down(containers: containers) { print($0) }
        }
    }
}
