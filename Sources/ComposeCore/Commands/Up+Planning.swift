import Foundation

extension Up {
    typealias StartupPlan = ProjectUpPlanning.Plan

    func resolveStartupPlan(machineName: String?) throws -> StartupPlan {
        try ProjectUpPlanning.resolve(
            inputs: projectOptions.composeCommandInputs(
                profiles: profileOptions.profiles,
                machineName: machineName
            ),
            scaleOverrides: try scaleOptions.resolvedScaleOverrides(),
            machineName: machineName
        )
    }
}
