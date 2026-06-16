import Foundation

extension Up {
    typealias StartupPlan = ProjectUpPlanning.Plan

    func resolveStartupPlan(machineName: String?, dryRun: Bool) throws -> StartupPlan {
        try ProjectUpPlanning.resolve(
            inputs: projectOptions.composeCommandInputs(
                profiles: profileOptions.profiles,
                machineName: machineName
            ),
            scaleOverrides: try scaleOptions.resolvedScaleOverrides(),
            machineName: machineName,
            dryRun: dryRun
        )
    }
}
