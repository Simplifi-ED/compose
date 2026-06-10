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
        let fileURLs = try projectOptions.resolvedFileURLsIfPresent()
        let projectName = try projectOptions.resolvedProjectName(fileURL: fileURLs?.first)
        let containers = try await ContainerDiscovery.containers(forProject: projectName)

        let useOrderedShutdown = fileURLs != nil && !projectOptions.hasExplicitProjectName

        if useOrderedShutdown, let fileURLs {
            let composeFile = try ComposeParser.parseForShutdown(fileURLs: fileURLs)
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
