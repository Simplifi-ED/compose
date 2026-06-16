import Foundation

package struct ProjectUpRequest: Sendable {
    package let inputs: ComposeCommandInputs
    package let dryRun: Bool
    package let removeOrphans: Bool
    package let maxConcurrent: Int?
    package let scaleOverrides: [String: Int]

    package init(
        inputs: ComposeCommandInputs,
        dryRun: Bool = false,
        removeOrphans: Bool = false,
        maxConcurrent: Int? = nil,
        scaleOverrides: [String: Int] = [:]
    ) {
        self.inputs = inputs
        self.dryRun = dryRun
        self.removeOrphans = removeOrphans
        self.maxConcurrent = maxConcurrent
        self.scaleOverrides = scaleOverrides
    }
}

package struct ProjectUpExecution: Sendable {
    package let progress: WaveProgressHandlers?

    package init(progress: WaveProgressHandlers? = nil) {
        self.progress = progress
    }
}

package enum ProjectUpRun {
    package static func run(
        _ request: ProjectUpRequest,
        execution: ProjectUpExecution = ProjectUpExecution()
    ) async throws -> ProjectMutationResult {
        let plan = try ProjectUpPlanning.resolve(
            inputs: request.inputs,
            scaleOverrides: request.scaleOverrides,
            machineName: request.inputs.machineName,
            requireExplicitFiles: true,
            dryRun: request.dryRun
        )
        if request.dryRun {
            return ProjectMutationResult(affectedContainers: plan.plans.map(\.name))
        }

        let machineContext = try await MachineContext.resolve(machineName: request.inputs.machineName)
            .ensureBooted()
        try await executeStartup(
            plan: plan,
            request: request,
            execution: execution,
            machineContext: machineContext
        )
        return ProjectMutationResult(affectedContainers: plan.plans.map(\.name))
    }

    package static func executeStartup(
        plan: ProjectUpPlanning.Plan,
        request: ProjectUpRequest,
        execution: ProjectUpExecution,
        machineContext: MachineContext
    ) async throws {
        try await BuildRunner.buildAll(
            plan.buildPlans,
            progress: nil,
            dryRunManifest: nil,
            machineContext: machineContext
        )
        try await NetworkRunner.createAll(
            plan.networkPlans,
            projectName: plan.projectName,
            machineContext: machineContext
        )
        try await VolumeRunner.createAll(
            plan.volumePlans,
            projectName: plan.projectName,
            machineContext: machineContext
        )
        try await executeWaves(
            plan: plan,
            request: request,
            execution: execution,
            machineContext: machineContext
        )
    }

    package static func executeWaves(
        plan: ProjectUpPlanning.Plan,
        request: ProjectUpRequest,
        execution: ProjectUpExecution,
        machineContext: MachineContext
    ) async throws {
        let wavePolicy = WaveExecutionPolicy(maxConcurrent: request.maxConcurrent)
        if request.removeOrphans {
            try await UpOrphanRemoval.removeBeforeStartupBestEffort(
                projectName: plan.projectName,
                composeFile: plan.composeFile,
                activeProfiles: plan.activeProfiles,
                execution: wavePolicy,
                machineContext: machineContext
            )
        }
        try await ServiceRunner.up(
            layers: plan.layers,
            progress: execution.progress,
            healthContext: plan.healthContext,
            execution: wavePolicy,
            machineContext: machineContext
        )
    }
}
