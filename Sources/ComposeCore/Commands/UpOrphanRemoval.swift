import Foundation

enum UpOrphanRemoval {
    static func removeBeforeStartup(
        projectName: String,
        composeFile: ComposeFile,
        activeProfiles: Set<String>
    ) async throws {
        let discovered = try await ContainerDiscovery.containers(forProject: projectName)
        let orphans = OrphanRemoval.orphans(
            in: discovered,
            composeFile: composeFile,
            policy: .beforeUp(activeProfiles: activeProfiles)
        )
        guard !orphans.isEmpty else { return }

        try await OrphanRemoval.removeOrphans(orphans)
        WorkspaceHygieneOutput.printOrphanRemovalSummary(
            count: orphans.count,
            names: orphans.map(\.name)
        )
    }
}
