import Foundation

extension Run {
    struct ResolvedRun: Sendable {
        let fileURLs: [URL]
        let composeFile: ComposeFile
        let projectName: String
        let composeService: ComposeService
        let serviceDirectory: URL
        let buildPlans: [BuildRunner.Plan]
        let plan: ServicePlan
        let networkPlans: [NetworkPlanning.Plan]
        let volumePlans: [VolumePlanning.Plan]
    }

    func resolveRun() throws -> ResolvedRun {
        let fileURLs = try projectOptions.resolvedFileURLs()
        let composeFile = try ComposeParser.parse(fileURLs: fileURLs)
        let projectName = try projectOptions.resolvedProjectName(
            composeFile: composeFile,
            fileURL: fileURLs[0]
        )
        guard let composeService = composeFile.services[service] else {
            throw ComposeError.undefinedService(service: service)
        }

        let composeDirectory = fileURLs[0].deletingLastPathComponent()
        let serviceDirectory = composeService.projectDirectory(orDefault: composeDirectory)
        let buildPlans = try BuildRunner.runBuildPlans(
            targetServiceName: service,
            composeFile: composeFile,
            projectName: projectName,
            composeDirectory: composeDirectory
        )
        let plan = try makeRunPlan(
            composeFile: composeFile,
            projectName: projectName,
            serviceDirectory: serviceDirectory,
            composeService: composeService
        )
        let networkPlans = try NetworkPlanning.plans(
            composeFile: composeFile,
            projectName: projectName,
            activeServiceNames: [service]
        )
        let volumePlans = try VolumePlanning.plans(
            composeFile: composeFile,
            projectName: projectName,
            activeServiceNames: [service]
        )
        return ResolvedRun(
            fileURLs: fileURLs,
            composeFile: composeFile,
            projectName: projectName,
            composeService: composeService,
            serviceDirectory: serviceDirectory,
            buildPlans: buildPlans,
            plan: plan,
            networkPlans: networkPlans,
            volumePlans: volumePlans
        )
    }

    func prepareRunResources(
        buildPlans: [BuildRunner.Plan],
        networkPlans: [NetworkPlanning.Plan],
        volumePlans: [VolumePlanning.Plan],
        projectName: String,
        machineContext: MachineContext = .applicationSandbox
    ) async throws {
        if !buildPlans.isEmpty {
            // ponytail: host run; ProgressSetting.none so compose owns pull stderr.
            try await BuildRunner.buildAll(
                buildPlans,
                progress: ProgressSetting.none,
                dryRunManifest: nil
            )
        }
        try await NetworkRunner.createAll(
            networkPlans,
            projectName: projectName,
            machineContext: machineContext
        )
        try await VolumeRunner.createAll(
            volumePlans,
            projectName: projectName,
            machineContext: machineContext
        )
    }
}
