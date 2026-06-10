import ArgumentParser
import Foundation

public struct Up: AsyncParsableCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        abstract: "Create and start containers defined in the compose file."
    )

    @OptionGroup
    var projectOptions: ProjectOptions

    public func run() async throws {
        let fileURLs = try projectOptions.resolvedFileURLs()
        let projectName = try projectOptions.resolvedProjectName(fileURL: fileURLs[0])
        let composeFile = try ComposeParser.parse(fileURLs: fileURLs)
        let composeDirectory = fileURLs[0].deletingLastPathComponent()
        let layers = try ServicePlanner.startupLayers(
            for: composeFile,
            projectName: projectName,
            composeDirectory: composeDirectory
        )

        try await ServiceRunner.up(layers: layers)

        for plan in layers.flatMap({ $0 }) {
            print(plan.name)
        }
    }
}
