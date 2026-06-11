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

    @OptionGroup
    var shutdownTimeoutOptions: ShutdownTimeoutOptions

    @OptionGroup
    var profileOptions: ProfileOptions

    @Flag(
        name: .long,
        help: "After startup, follow service logs in the foreground until services exit or you interrupt."
    )
    var attach = false

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
            composeDirectory: composeDirectory,
            activeProfiles: profileOptions.activeProfileSet
        )
        let plans = layers.flatMap { $0 }

        let orchestration = makeProgressOrchestration(
            display: progressOptions.resolvedDisplay(),
            phase: .starting
        )
        try await runOrchestrationCommand(
            lines: orchestration.lines,
            interruptedMessage: "Startup interrupted. Started containers are still running."
        ) {
            try await ServiceRunner.up(layers: layers, progress: orchestration.handlers)
        }

        for plan in plans {
            print(plan.name)
        }

        guard attach else { return }

        let shutdownContext = ProjectShutdownContext(
            projectName: projectName,
            composeFile: composeFile,
            fileURLs: fileURLs,
            options: shutdownTimeoutOptions.gracefulStopOptions()
        )
        try await AttachAfterUp.run(
            plans: plans,
            shutdownContext: shutdownContext,
            mode: TerminalMode.resolve()
        )
    }
}
