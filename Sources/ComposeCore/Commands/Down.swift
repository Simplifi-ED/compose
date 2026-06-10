import ArgumentParser
import Foundation

public struct Down: AsyncParsableCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        abstract: "Stop containers defined in the compose file."
    )

    @OptionGroup
    var projectOptions: ProjectOptions

    public func run() async throws {
        let fileURL = try projectOptions.resolvedFileURL()
        let projectName = projectOptions.resolvedProjectName(fileURL: fileURL)
        let composeFile = try ComposeParser.parse(fileURL: fileURL)
        let plans = try ServicePlanner.plans(for: composeFile, projectName: projectName)
        let containerIDs = plans.map(\.containerID)

        try await ServiceRunner.down(containerIDs: containerIDs)

        for containerID in containerIDs {
            print(containerID)
        }
    }
}
