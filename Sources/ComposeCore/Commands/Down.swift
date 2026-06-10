import ArgumentParser
import Foundation

public struct Down: AsyncParsableCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        abstract: "Stop and remove containers for the compose project."
    )

    @OptionGroup
    var projectOptions: ProjectOptions

    @OptionGroup
    var progressOptions: ProgressOptions

    public func run() async throws {
        let context = try projectOptions.resolvedLabelCommandContext()
        let containers = try await ContainerDiscovery.containers(forProject: context.projectName)

        let useOrderedShutdown = context.fileURLs != nil && !projectOptions.hasExplicitProjectName

        let displayNames = Dictionary(
            containers.map {
                ($0.name, progressServiceLabel(containerName: $0.name, serviceName: $0.serviceName))
            },
            uniquingKeysWith: { _, last in last }
        )

        let orchestration = makeProgressOrchestration(
            display: progressOptions.resolvedDisplay(),
            phase: .stopping,
            label: { displayNames[$0] ?? $0 }
        )
        try await runOrchestrationCommand(
            lines: orchestration.lines,
            interruptedMessage: "Shutdown interrupted. Some containers may still be running."
        ) {
            if useOrderedShutdown, let composeFile = context.composeFile {
                let layers = try ServicePlanner.shutdownContainerLayers(
                    for: composeFile,
                    containers: containers
                )
                let unmapped = ServicePlanner.unmappedContainers(
                    in: containers,
                    composeFile: composeFile
                )
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
                try await ServiceRunner.down(
                    layers: layers,
                    onRemoved: { print($0) },
                    progress: orchestration.handlers
                )
            } else {
                try await ServiceRunner.down(
                    containers: containers,
                    onRemoved: { print($0) },
                    progress: orchestration.handlers
                )
            }
        }
    }
}
