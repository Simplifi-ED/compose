import Foundation

extension Up {
    struct StartupPlan: Sendable {
        let fileURLs: [URL]
        let composeFile: ComposeFile
        let projectName: String
        let buildPlans: [BuildRunner.Plan]
        let layers: [[ServicePlan]]
        let plans: [ServicePlan]
        let healthContext: HealthWaitContext
    }

    func resolveStartupPlan(machineName: String?) throws -> StartupPlan {
        let fileURLs = try projectOptions.resolvedFileURLs()
        let composeFile = try ComposeParser.parse(fileURLs: fileURLs)
        let projectName = try projectOptions.resolvedProjectName(
            composeFile: composeFile,
            fileURL: fileURLs[0]
        )
        let composeDirectory = fileURLs[0].deletingLastPathComponent()
        let scaleOverrides = try scaleOptions.resolvedScaleOverrides()
        let buildPlans = try resolveBuildPlans(
            composeFile: composeFile,
            projectName: projectName,
            composeDirectory: composeDirectory
        )
        let layers = try ServicePlanner.startupLayers(
            for: composeFile,
            projectName: projectName,
            composeDirectory: composeDirectory,
            activeProfiles: profileOptions.activeProfileSet,
            scaleOverrides: scaleOverrides,
            machineName: machineName
        )
        let plans = layers.flatMap { $0 }
        let healthContext = HealthWaitContext(
            services: composeFile.services,
            projectName: projectName,
            scaleOverrides: scaleOverrides
        )
        return StartupPlan(
            fileURLs: fileURLs,
            composeFile: composeFile,
            projectName: projectName,
            buildPlans: buildPlans,
            layers: layers,
            plans: plans,
            healthContext: healthContext
        )
    }
}
