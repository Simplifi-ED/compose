import Foundation

package enum UpOrphanRemoval {
    /// Best-effort pre-startup orphan cleanup for `up --remove-orphans`.
    /// Discovery and removal failures warn and continue; cancellation propagates.
    package static func removeBeforeStartupBestEffort(
        projectName: String,
        composeFile: ComposeFile,
        activeProfiles: Set<String>,
        execution: WaveExecutionPolicy = .unlimited
    ) async throws {
        let discovered: [DiscoveredContainer]
        do {
            discovered = try await ContainerDiscovery.containers(forProject: projectName)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            WorkspaceHygieneOutput.warnOrphanRemovalSkipped(
                WorkspaceHygieneOutput.listContainersFailureMessage(error)
            )
            return
        }

        try await removeDiscoveredOrphansBestEffort(
            discovered: discovered,
            composeFile: composeFile,
            activeProfiles: activeProfiles,
            execution: execution
        )
    }

    package static func removeDiscoveredOrphansBestEffort(
        discovered: [DiscoveredContainer],
        composeFile: ComposeFile,
        activeProfiles: Set<String>,
        execution: WaveExecutionPolicy = .unlimited
    ) async throws {
        let orphans = OrphanRemoval.orphans(
            in: discovered,
            composeFile: composeFile,
            policy: .beforeUp(activeProfiles: activeProfiles)
        )
        guard !orphans.isEmpty else { return }

        do {
            try await OrphanRemoval.removeOrphans(orphans, execution: execution)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            WorkspaceHygieneOutput.warnOrphanRemovalSkipped(
                WorkspaceHygieneOutput.orphanRemovalFailureMessage(error)
            )
        }
    }

}
