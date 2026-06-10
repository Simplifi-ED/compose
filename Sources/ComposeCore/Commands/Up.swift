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
        let fileURL = try projectOptions.resolvedFileURL()
        let projectName = try projectOptions.resolvedProjectName(fileURL: fileURL)
        let composeFile = try ComposeParser.parse(fileURL: fileURL)
        let composeDirectory = fileURL.deletingLastPathComponent()
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
