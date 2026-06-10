import ArgumentParser
import Foundation

public struct Up: AsyncParsableCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        abstract: "Create and start containers defined in the compose file."
    )

    @OptionGroup
    var projectOptions: ProjectOptions

    @OptionGroup
    var progressOptions: ProgressOptions

    public func run() async throws {
        let fileURLs = try projectOptions.resolvedFileURLs()
        let composeFile = try ComposeParser.parse(fileURLs: fileURLs)
        let projectName = try projectOptions.resolvedProjectName(
            composeFile: composeFile,
            fileURL: fileURLs[0]
        )
        let composeDirectory = fileURLs[0].deletingLastPathComponent()
        let layers = try ServicePlanner.startupLayers(
            for: composeFile,
            projectName: projectName,
            composeDirectory: composeDirectory
        )

        let lines = ProgressLines(display: progressOptions.resolvedDisplay(), phase: .starting)
        let progress = WaveProgressHandlers(
            onWaveStart: { wave, total, services in
                await lines.beginWave(wave: wave, total: total, services: services)
            },
            onServiceComplete: { service, succeeded in
                await lines.markComplete(service: service, succeeded: succeeded)
            },
            onWaveComplete: { _ in
                await lines.finishWave()
            }
        )

        do {
            try await ServiceRunner.up(layers: layers, progress: progress)
        } catch {
            await lines.finish()
            throw error
        }
        await lines.finish()

        for plan in layers.flatMap({ $0 }) {
            print(plan.name)
        }
    }
}
