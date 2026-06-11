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

    @OptionGroup
    var scaleOptions: ScaleOptions

    @OptionGroup
    var workspaceHygiene: WorkspaceHygieneOptions

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

        let scaleOverrides = try scaleOptions.resolvedScaleOverrides()
        let layers = try ServicePlanner.startupLayers(
            for: composeFile,
            projectName: projectName,
            composeDirectory: composeDirectory,
            activeProfiles: profileOptions.activeProfileSet,
            scaleOverrides: scaleOverrides
        )
        let plans = layers.flatMap { $0 }
        let healthContext = HealthWaitContext(
            services: composeFile.services,
            projectName: projectName,
            scaleOverrides: scaleOverrides
        )

        try await orchestrateStartup(
            projectName: projectName,
            composeFile: composeFile,
            layers: layers,
            healthContext: healthContext
        )

        try await finishStartup(
            plans: plans,
            projectName: projectName,
            composeFile: composeFile,
            fileURLs: fileURLs
        )
    }

    private func orchestrateStartup(
        projectName: String,
        composeFile: ComposeFile,
        layers: [[ServicePlan]],
        healthContext: HealthWaitContext
    ) async throws {
        let shouldRemoveOrphans = workspaceHygiene.shouldRemoveOrphans
        let activeProfiles = profileOptions.activeProfileSet
        let orchestration = makeProgressOrchestration(
            display: progressOptions.resolvedDisplay(),
            phase: .starting
        )
        try await runOrchestrationCommand(
            lines: orchestration.lines,
            interruptedMessage: "Startup interrupted. Started containers are still running."
        ) {
            if shouldRemoveOrphans {
                try await UpOrphanRemoval.removeBeforeStartupBestEffort(
                    projectName: projectName,
                    composeFile: composeFile,
                    activeProfiles: activeProfiles
                )
            }
            try await ServiceRunner.up(
                layers: layers,
                progress: orchestration.handlers,
                healthContext: healthContext
            )
        }
    }

    private func finishStartup(
        plans: [ServicePlan],
        projectName: String,
        composeFile: ComposeFile,
        fileURLs: [URL]
    ) async throws {
        for line in UpStartupSummary.lines(for: plans) {
            print(line)
        }
        try await attachIfRequested(
            projectName: projectName,
            composeFile: composeFile,
            fileURLs: fileURLs,
            plans: plans
        )
    }

    private func attachIfRequested(
        projectName: String,
        composeFile: ComposeFile,
        fileURLs: [URL],
        plans: [ServicePlan]
    ) async throws {
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
