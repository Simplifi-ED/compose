import ArgumentParser
import Foundation

public struct Config: AsyncParsableCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        abstract: "Print the fully resolved compose configuration."
    )

    @OptionGroup
    var projectOptions: ProjectOptions

    @OptionGroup
    var profileOptions: ProfileOptions

    @OptionGroup
    var scaleOptions: ScaleOptions

    @Flag(
        name: .long,
        help: "Validate without printing the resolved configuration."
    )
    var quiet = false

    public func run() async throws {
        let fileURLs = try projectOptions.resolvedFileURLs()
        let composeFile = try ComposeParser.parse(fileURLs: fileURLs)
        let projectName = try projectOptions.resolvedProjectName(
            composeFile: composeFile,
            fileURL: fileURLs[0]
        )
        let scaleOverrides = try scaleOptions.resolvedScaleOverrides()
        if let yaml = try ComposeConfigResolver.resolveOutput(
            fileURLs: fileURLs,
            projectName: projectName,
            activeProfiles: profileOptions.activeProfileSet,
            scaleOverrides: scaleOverrides,
            quiet: quiet
        ) {
            print(yaml, terminator: "")
        }
    }
}
