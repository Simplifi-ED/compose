import Foundation

package struct ProjectUpRequest: Sendable {
    package let inputs: ComposeCommandInputs
    package let dryRun: Bool
    package let removeOrphans: Bool
    package let maxConcurrent: Int?

    package init(
        inputs: ComposeCommandInputs,
        dryRun: Bool = false,
        removeOrphans: Bool = false,
        maxConcurrent: Int? = nil
    ) {
        self.inputs = inputs
        self.dryRun = dryRun
        self.removeOrphans = removeOrphans
        self.maxConcurrent = maxConcurrent
    }
}

package enum ProjectUpRun {
    package static func run(_ request: ProjectUpRequest) async throws -> ComposeXPCMutationResponse {
        if request.inputs.machineName != nil {
            throw ComposeError.machineUnsupportedCommand("up")
        }

        let plan = try resolveStartupPlan(inputs: request.inputs)
        if request.dryRun {
            return ComposeXPCMutationResponse(
                exitStatus: 0,
                affectedContainers: plan.plans.map(\.name)
            )
        }

        let machineContext = try await MachineContext.resolve(machineName: nil).ensureBooted()
        try await executeStartup(plan: plan, request: request, machineContext: machineContext)
        return ComposeXPCMutationResponse(
            exitStatus: 0,
            affectedContainers: plan.plans.map(\.name)
        )
    }

    private struct StartupPlan: Sendable {
        let fileURLs: [URL]
        let composeFile: ComposeFile
        let projectName: String
        let buildPlans: [BuildRunner.Plan]
        let networkPlans: [NetworkPlanning.Plan]
        let volumePlans: [VolumePlanning.Plan]
        let layers: [[ServicePlan]]
        let plans: [ServicePlan]
        let healthContext: HealthWaitContext
        let activeProfiles: Set<String>
    }

    private struct StartupPlanSeed: Sendable {
        let fileURLs: [URL]
        let composeFile: ComposeFile
        let projectName: String
        let layers: [[ServicePlan]]
        let composeDirectory: URL
        let activeProfiles: Set<String>
    }

    private static func resolveStartupPlan(inputs: ComposeCommandInputs) throws -> StartupPlan {
        try ComposePathValidation.validateComposeFilePaths(inputs.files)
        guard !inputs.files.isEmpty else {
            throw ComposeXPCError.invalidRequest(
                "up requires at least one compose file path in files[]"
            )
        }
        let fileURLs = try ComposeFileResolution.resolved(
            files: try ComposeFileResolution.discover(cliFiles: inputs.files)
        )
        let composeFile = try ComposeParser.parse(fileURLs: fileURLs)
        let projectName = try ProjectNameResolver.resolve(
            cliProjectName: inputs.projectName,
            composeName: composeFile.name,
            firstFileURL: fileURLs[0]
        )
        let profileResolution = ProfileResolution.resolve(
            cliProfiles: inputs.profiles,
            environment: inputs.environment
        )
        let composeDirectory = fileURLs[0].deletingLastPathComponent()
        let layers = try ServicePlanner.startupLayers(
            for: composeFile,
            projectName: projectName,
            composeDirectory: composeDirectory,
            activeProfiles: profileResolution.activeProfiles,
            scaleOverrides: [:],
            machineName: nil
        )
        return try makeStartupPlan(
            StartupPlanSeed(
                fileURLs: fileURLs,
                composeFile: composeFile,
                projectName: projectName,
                layers: layers,
                composeDirectory: composeDirectory,
                activeProfiles: profileResolution.activeProfiles
            )
        )
    }

    private static func makeStartupPlan(_ seed: StartupPlanSeed) throws -> StartupPlan {
        let plans = seed.layers.flatMap { $0 }
        let activeServiceNames = Set(plans.map(\.serviceName))
        let buildPlans = try BuildRunner.plans(
            composeFile: seed.composeFile,
            projectName: seed.projectName,
            composeDirectory: seed.composeDirectory,
            activeProfiles: seed.activeProfiles
        )
        let networkPlans = try NetworkPlanning.plans(
            composeFile: seed.composeFile,
            projectName: seed.projectName,
            activeServiceNames: activeServiceNames
        )
        let volumePlans = try VolumePlanning.plans(
            composeFile: seed.composeFile,
            projectName: seed.projectName,
            activeServiceNames: activeServiceNames
        )
        return StartupPlan(
            fileURLs: seed.fileURLs,
            composeFile: seed.composeFile,
            projectName: seed.projectName,
            buildPlans: buildPlans,
            networkPlans: networkPlans,
            volumePlans: volumePlans,
            layers: seed.layers,
            plans: plans,
            healthContext: HealthWaitContext(
                services: seed.composeFile.services,
                projectName: seed.projectName,
                scaleOverrides: [:]
            ),
            activeProfiles: seed.activeProfiles
        )
    }

    private static func executeStartup(
        plan: StartupPlan,
        request: ProjectUpRequest,
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
        let execution = WaveExecutionPolicy(maxConcurrent: request.maxConcurrent)
        if request.removeOrphans {
            try await UpOrphanRemoval.removeBeforeStartupBestEffort(
                projectName: plan.projectName,
                composeFile: plan.composeFile,
                activeProfiles: plan.activeProfiles,
                execution: execution,
                machineContext: machineContext
            )
        }
        try await ServiceRunner.up(
            layers: plan.layers,
            progress: nil,
            healthContext: plan.healthContext,
            execution: execution,
            machineContext: machineContext
        )
    }
}
