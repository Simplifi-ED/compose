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
    var parallelOptions: ParallelOptions

    @OptionGroup
    var workspaceHygiene: WorkspaceHygieneOptions

    @OptionGroup
    var dryRunOptions: DryRunOptions

    @Flag(
        name: .long,
        help: "After startup, follow service logs in the foreground until services exit or you interrupt."
    )
    var attach = false

    public func run() async throws {
        try parallelOptions.validate()
        let fileURLs = try projectOptions.resolvedFileURLs()
        let composeFile = try ComposeParser.parse(fileURLs: fileURLs)
        let projectName = try projectOptions.resolvedProjectName(
            composeFile: composeFile,
            fileURL: fileURLs[0]
        )
        let composeDirectory = fileURLs[0].deletingLastPathComponent()

        let scaleOverrides = try scaleOptions.resolvedScaleOverrides()
        let buildPlans = try resolveBuildPlans(
            composeFile: composeFile,
            projectName: projectName,
            composeDirectory: composeDirectory
        )
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

        if dryRunOptions.isEnabled {
            try await runDryRun(
                projectName: projectName,
                composeFile: composeFile,
                layers: layers,
                healthContext: healthContext,
                buildPlans: buildPlans
            )
            return
        }

        try await executeBuildPlans(buildPlans, dryRunManifest: nil)

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
}
