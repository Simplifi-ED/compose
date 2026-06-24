import Foundation

extension Up {
    struct LiveInput: Sendable {
        let plan: StartupPlan
        let machineContext: MachineContext
        let installHostDNS: Bool
    }

    func runLive(_ input: LiveInput) async throws {
        try await executeBuildPlans(
            input.plan.buildPlans,
            dryRunManifest: nil,
            machineContext: input.machineContext
        )
        try await NetworkRunner.createAll(
            input.plan.networkPlans,
            projectName: input.plan.projectName,
            machineContext: input.machineContext
        )
        try await VolumeRunner.createAll(
            input.plan.volumePlans,
            projectName: input.plan.projectName,
            machineContext: input.machineContext
        )
        try await orchestrateStartup(
            plan: input.plan,
            machineContext: input.machineContext
        )
        try await finishStartup(
            plans: input.plan.plans,
            projectName: input.plan.projectName,
            composeFile: input.plan.composeFile,
            fileURLs: input.plan.fileURLs,
            machineContext: input.machineContext,
            input: input
        )
    }

    func orchestrateStartup(
        plan: StartupPlan,
        machineContext: MachineContext
    ) async throws {
        let orchestration = makeProgressOrchestration(
            display: progressOptions.resolvedDisplay(),
            phase: .starting
        )
        let imagePullOutput = progressOptions.resolvedImagePullOutput()
        let request = ProjectUpRequest(
            inputs: projectOptions.composeCommandInputs(
                profiles: profileOptions.profiles,
                machineName: machineContext.machineName
            ),
            removeOrphans: workspaceHygiene.shouldRemoveOrphans,
            maxConcurrent: parallelOptions.resolvedMaxConcurrent(),
            scaleOverrides: (try? scaleOptions.resolvedScaleOverrides()) ?? [:]
        )
        try await runOrchestrationCommand(
            lines: orchestration.lines,
            interruptedMessage: "Startup interrupted. Started containers are still running."
        ) {
            try await ProjectUpRun.executeWaves(
                plan: plan,
                request: request,
                execution: ProjectUpExecution(
                    progress: orchestration.handlers,
                    imagePullOutput: imagePullOutput
                ),
                machineContext: machineContext
            )
        }
    }

    func finishStartup(
        plans: [ServicePlan],
        projectName: String,
        composeFile: ComposeFile,
        fileURLs: [URL],
        machineContext: MachineContext,
        input: LiveInput? = nil
    ) async throws {
        for line in UpStartupSummary.lines(for: plans) {
            print(line)
        }
        await ClockSyncCoordinator.shared.syncIfNeeded(reason: .afterUp)
        if let input {
            await installHostDNSAfterStartupIfRequested(input, machineContext: machineContext)
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
