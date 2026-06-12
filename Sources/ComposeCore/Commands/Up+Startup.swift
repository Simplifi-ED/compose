import Foundation

extension Up {
    func orchestrateStartup(
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

    func finishStartup(
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

    func attachIfRequested(
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
