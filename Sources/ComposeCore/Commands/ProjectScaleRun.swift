import Foundation

package struct ProjectScaleRequest: Sendable {
    package let inputs: ComposeCommandInputs
    package let dryRun: Bool
    package let maxConcurrent: Int?
    package let scaleOverrides: [String: Int]

    package init(
        inputs: ComposeCommandInputs,
        dryRun: Bool = false,
        maxConcurrent: Int? = nil,
        scaleOverrides: [String: Int]
    ) {
        self.inputs = inputs
        self.dryRun = dryRun
        self.maxConcurrent = maxConcurrent
        self.scaleOverrides = scaleOverrides
    }
}

package enum ProjectScaleRun {
    package static func run(
        _ request: ProjectScaleRequest,
        imagePullOutput: ImagePullOutput? = .headlessHost
    ) async throws -> ProjectMutationResult {
        let plan = try ProjectScalePlanning.resolve(
            inputs: request.inputs,
            scaleOverrides: request.scaleOverrides,
            machineName: request.inputs.machineName,
            requireExplicitFiles: true
        )
        let prepared = try await prepareReconcile(
            plan: plan,
            request: request
        )
        if request.dryRun {
            return ProjectMutationResult(
                affectedContainers: prepared.reconcilePlan.toStop + prepared.reconcilePlan.toStart.map(\.name)
            )
        }
        try await provisionInfrastructure(
            plan: plan,
            machineContext: prepared.machineContext,
            imagePullOutput: imagePullOutput
        )
        let affected = try await ScaleReconcile.execute(
            plan: prepared.reconcilePlan,
            projectName: plan.projectName,
            imagePullOutput: imagePullOutput,
            machineContext: prepared.machineContext,
            maxConcurrent: request.maxConcurrent
        )
        return ProjectMutationResult(affectedContainers: affected)
    }

    private struct PreparedReconcile: Sendable {
        let machineContext: MachineContext
        let reconcilePlan: ScaleReconcile.Plan
    }

    private static func prepareReconcile(
        plan: ProjectScalePlanning.Plan,
        request: ProjectScaleRequest
    ) async throws -> PreparedReconcile {
        let machineResolution = try await MachineContext.resolve(machineName: request.inputs.machineName)
        let machineContext: MachineContext
        if request.dryRun {
            machineContext = machineResolution
        } else {
            machineContext = try await machineResolution.ensureBooted()
        }
        let containers = try await ContainerDiscovery.projectContainers(
            forProject: plan.projectName,
            machineContext: machineContext
        )
        let reconcilePlan = try ScaleReconcile.plan(
            ScaleReconcile.PlanningInput(
                composeFile: plan.composeFile,
                projectName: plan.projectName,
                composeDirectory: plan.composeDirectory,
                scaleOverrides: plan.scaleOverrides,
                containers: containers,
                activeProfiles: plan.activeProfiles,
                machineName: request.inputs.machineName,
                requireAgentReachability: !request.dryRun
            )
        )
        return PreparedReconcile(machineContext: machineContext, reconcilePlan: reconcilePlan)
    }

    private static func provisionInfrastructure(
        plan: ProjectScalePlanning.Plan,
        machineContext: MachineContext,
        imagePullOutput: ImagePullOutput?
    ) async throws {
        try await BuildRunner.buildAll(
            plan.buildPlans,
            progress: imagePullOutput != nil && !machineContext.isMachineMode ? ProgressSetting.none : nil,
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
    }
}
