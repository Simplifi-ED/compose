import Foundation

extension Up {
    func resolveBuildPlans(
        composeFile: ComposeFile,
        projectName: String,
        composeDirectory: URL
    ) throws -> [BuildRunner.Plan] {
        try BuildRunner.plans(
            composeFile: composeFile,
            projectName: projectName,
            composeDirectory: composeDirectory,
            activeProfiles: profileOptions.activeProfileSet
        )
    }

    func executeBuildPlans(
        _ buildPlans: [BuildRunner.Plan],
        dryRunManifest: DryRunManifest?,
        machineContext: MachineContext
    ) async throws {
        let buildProgress: ProgressSetting? = {
            guard dryRunManifest == nil else { return nil }
            if machineContext.isMachineMode { return progressOptions.progress }
            return ProgressSetting.none
        }()
        try await BuildRunner.buildAll(
            buildPlans,
            progress: buildProgress,
            dryRunManifest: dryRunManifest,
            machineContext: machineContext
        )
    }
}
