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

        // Progress shows compose service names where known; stdout keeps container names.
        let displayNames = Dictionary(
            uniqueKeysWithValues: containers.map { ($0.name, $0.serviceName ?? $0.name) }
        )
        let lines = ProgressLines(display: progressOptions.resolvedDisplay(), phase: .stopping)
        let progress = WaveProgressHandlers(
            onWaveStart: { wave, total, names in
                await lines.beginWave(wave: wave, total: total, services: names.map { displayNames[$0] ?? $0 })
            },
            onServiceComplete: { name, succeeded in
                await lines.markComplete(service: displayNames[name] ?? name, succeeded: succeeded)
            },
            onWaveComplete: { _ in
                await lines.finishWave()
            }
        )

        do {
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
                try await ServiceRunner.down(layers: layers, onRemoved: { print($0) }, progress: progress)
            } else {
                try await ServiceRunner.down(containers: containers, onRemoved: { print($0) }, progress: progress)
            }
        } catch {
            await lines.finish()
            throw error
        }
        await lines.finish()
    }
}
