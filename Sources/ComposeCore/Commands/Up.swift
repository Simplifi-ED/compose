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
        let plans = try ServicePlanner.plans(for: composeFile, projectName: projectName)

        try await ServiceRunner.up(plans: plans)

        for plan in plans {
            print(plan.name)
        }
    }
}
