import Foundation

extension Up {
    struct LiveInput: Sendable {
        let buildPlans: [BuildRunner.Plan]
        let networkPlans: [NetworkPlanning.Plan]
        let volumePlans: [VolumePlanning.Plan]
        let projectName: String
        let composeFile: ComposeFile
        let fileURLs: [URL]
        let layers: [[ServicePlan]]
        let plans: [ServicePlan]
        let healthContext: HealthWaitContext
        let machineContext: MachineContext
    }

    func runLive(_ input: LiveInput) async throws {
        try await executeBuildPlans(
            input.buildPlans,
            dryRunManifest: nil,
            machineContext: input.machineContext
        )
        try await NetworkRunner.createAll(
            input.networkPlans,
            projectName: input.projectName,
            machineContext: input.machineContext
        )
        try await VolumeRunner.createAll(
            input.volumePlans,
            projectName: input.projectName,
            machineContext: input.machineContext
        )
        try await orchestrateStartup(
            projectName: input.projectName,
            composeFile: input.composeFile,
            layers: input.layers,
            healthContext: input.healthContext,
            machineContext: input.machineContext
        )
        try await finishStartup(
            plans: input.plans,
            projectName: input.projectName,
            composeFile: input.composeFile,
            fileURLs: input.fileURLs,
            machineContext: input.machineContext
        )
    }

    func orchestrateStartup(
        projectName: String,
        composeFile: ComposeFile,
        layers: [[ServicePlan]],
        healthContext: HealthWaitContext,
        machineContext: MachineContext
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
                    execution: execution,
                    machineContext: machineContext
                )
            }
            try await ServiceRunner.up(
                layers: layers,
                progress: orchestration.handlers,
                healthContext: healthContext,
                execution: execution,
                machineContext: machineContext
            )
        }
    }

    func finishStartup(
        plans: [ServicePlan],
        projectName: String,
        composeFile: ComposeFile,
        fileURLs: [URL],
        machineContext: MachineContext
    ) async throws {
        for line in UpStartupSummary.lines(for: plans) {
            print(line)
        }
        try await attachIfRequested(
            projectName: projectName,
            composeFile: composeFile,
            fileURLs: fileURLs,
            plans: plans,
            machineContext: machineContext
        )
    }

    func attachIfRequested(
        projectName: String,
        composeFile: ComposeFile,
        fileURLs: [URL],
        plans: [ServicePlan],
        machineContext: MachineContext
    ) async throws {
        guard attach else { return }
        let shutdownContext = ProjectShutdownContext(
            projectName: projectName,
            composeFile: composeFile,
            fileURLs: fileURLs,
            options: shutdownTimeoutOptions.gracefulStopOptions(),
            machineContext: machineContext
        )
        try await AttachAfterUp.run(
            plans: plans,
            shutdownContext: shutdownContext,
            mode: TerminalMode.resolve(),
            machineContext: machineContext
        )
    }
}
