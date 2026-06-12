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
        try await BuildRunner.buildAll(
            buildPlans,
            progress: dryRunManifest == nil ? progressOptions.progress : nil,
            dryRunManifest: dryRunManifest,
            machineContext: machineContext
        )
    }
}
