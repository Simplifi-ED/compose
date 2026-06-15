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
        try await installHostDNSIfRequested(input)
        do {
            try await orchestrateStartup(
                plan: input.plan,
                machineContext: input.machineContext
            )
        } catch {
            await rollbackHostDNSIfNeeded(input, unless: error)
            throw error
        }
        try await finishStartup(
            plans: input.plan.plans,
            projectName: input.plan.projectName,
            composeFile: input.plan.composeFile,
            fileURLs: input.plan.fileURLs,
            machineContext: input.machineContext
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
                execution: ProjectUpExecution(progress: orchestration.handlers),
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
