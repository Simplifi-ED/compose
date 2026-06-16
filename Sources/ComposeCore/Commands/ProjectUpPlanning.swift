import Foundation

package enum ProjectUpPlanning {
    package struct Plan: Sendable {
        package let fileURLs: [URL]
        package let composeFile: ComposeFile
        package let projectName: String
        package let buildPlans: [BuildRunner.Plan]
        package let networkPlans: [NetworkPlanning.Plan]
        package let volumePlans: [VolumePlanning.Plan]
        package let layers: [[ServicePlan]]
        package let plans: [ServicePlan]
        package let healthContext: HealthWaitContext
        package let activeProfiles: Set<String>
    }

    package static func resolve(
        inputs: ComposeCommandInputs,
        scaleOverrides: [String: Int] = [:],
        machineName: String? = nil,
        requireExplicitFiles: Bool = false,
        dryRun: Bool = false
    ) throws -> Plan {
        try ComposePathValidation.validateComposeFilePaths(inputs.files)
        if requireExplicitFiles, inputs.files.isEmpty {
            throw ComposeError.invalidComposeFilePath(
                "up requires at least one compose file path in files[]"
            )
        }
        let fileURLs = try ComposeFileResolution.resolved(
            files: try ComposeFileResolution.discover(cliFiles: inputs.files)
        )
        let composeFile = try ComposeParser.parse(fileURLs: fileURLs)
        try DependencyValidation.validateMachineMode(
            services: composeFile.services,
            machineName: machineName
        )
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
            scaleOverrides: scaleOverrides,
            machineName: machineName,
            requireAgentReachability: !dryRun
        )
        return try assemblePlan(
            PlanSeed(
                fileURLs: fileURLs,
                composeFile: composeFile,
                projectName: projectName,
                layers: layers,
                composeDirectory: composeDirectory,
                activeProfiles: profileResolution.activeProfiles,
                scaleOverrides: scaleOverrides
            )
        )
    }

    private struct PlanSeed: Sendable {
        let fileURLs: [URL]
        let composeFile: ComposeFile
        let projectName: String
        let layers: [[ServicePlan]]
        let composeDirectory: URL
        let activeProfiles: Set<String>
        let scaleOverrides: [String: Int]
    }

    private static func assemblePlan(_ seed: PlanSeed) throws -> Plan {
        let plans = seed.layers.flatMap { $0 }
        let activeServiceNames = Set(plans.map(\.serviceName))
        return Plan(
            fileURLs: seed.fileURLs,
            composeFile: seed.composeFile,
            projectName: seed.projectName,
            buildPlans: try BuildRunner.plans(
                composeFile: seed.composeFile,
                projectName: seed.projectName,
                composeDirectory: seed.composeDirectory,
                activeProfiles: seed.activeProfiles
            ),
            networkPlans: try NetworkPlanning.plans(
                composeFile: seed.composeFile,
                projectName: seed.projectName,
                activeServiceNames: activeServiceNames
            ),
            volumePlans: try VolumePlanning.plans(
                composeFile: seed.composeFile,
                projectName: seed.projectName,
                activeServiceNames: activeServiceNames
            ),
            layers: seed.layers,
            plans: plans,
            healthContext: HealthWaitContext(
                services: seed.composeFile.services,
                projectName: seed.projectName,
                scaleOverrides: seed.scaleOverrides
            ),
            activeProfiles: seed.activeProfiles
        )
    }
}
