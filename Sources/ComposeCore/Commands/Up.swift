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

        let orchestration = makeProgressOrchestration(
            display: progressOptions.resolvedDisplay(),
            phase: .starting
        )
        try await runWithProgress(lines: orchestration.lines) {
            try await ServiceRunner.up(layers: layers, progress: orchestration.handlers)
        }

        for plan in layers.flatMap({ $0 }) {
            print(plan.name)
        }
    }
}
