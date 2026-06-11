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
                healthContext: healthContext
            )
            return
        }

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

    private func runDryRun(
        projectName: String,
        composeFile: ComposeFile,
        layers: [[ServicePlan]],
        healthContext: HealthWaitContext
    ) async throws {
        let manifest = DryRunManifest()
        let execution = WaveExecutionPolicy(maxConcurrent: parallelOptions.resolvedMaxConcurrent())

        if workspaceHygiene.shouldRemoveOrphans {
            try await recordOrphanTeardowns(
                manifest: manifest,
                projectName: projectName,
                composeFile: composeFile
            )
        }

        let hooks = await manifest.makeUpHooks()
        try await ServiceRunner.up(
            layers: layers,
            healthContext: healthContext,
            hooks: hooks,
            execution: execution,
            beforeWave: { index in
                await manifest.setUpWaveIndex(index)
            }
        )
        await manifest.printLines()
    }

    private func recordOrphanTeardowns(
        manifest: DryRunManifest,
        projectName: String,
        composeFile: ComposeFile
    ) async throws {
        let discovered: [DiscoveredContainer]
        do {
            discovered = try await ContainerDiscovery.containers(forProject: projectName)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            WorkspaceHygieneOutput.warnOrphanRemovalSkipped(
                WorkspaceHygieneOutput.listContainersFailureMessage(error)
            )
            return
        }
        let orphans = OrphanRemoval.orphans(
            in: discovered,
            composeFile: composeFile,
            policy: .beforeUp(activeProfiles: profileOptions.activeProfileSet)
        )
        for orphan in orphans {
            await manifest.recordTeardown(orphan.name, reason: .orphan)
        }
    }

    private func orchestrateStartup(
        projectName: String,
        composeFile: ComposeFile,
        layers: [[ServicePlan]],
        healthContext: HealthWaitContext
    ) async throws {
        let shouldRemoveOrphans = workspaceHygiene.shouldRemoveOrphans
        let activeProfiles = profileOptions.activeProfileSet
        let execution = WaveExecutionPolicy(maxConcurrent: parallelOptions.resolvedMaxConcurrent())
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
                    activeProfiles: activeProfiles,
                    execution: execution
                )
            }
            try await ServiceRunner.up(
                layers: layers,
                progress: orchestration.handlers,
                healthContext: healthContext,
                execution: execution
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
