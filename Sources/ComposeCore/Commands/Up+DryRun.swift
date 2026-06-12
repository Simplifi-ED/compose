import Foundation

extension Up {
    func runDryRun(
        projectName: String,
        composeFile: ComposeFile,
        layers: [[ServicePlan]],
        healthContext: HealthWaitContext,
        buildPlans: [BuildRunner.Plan]
    ) async throws {
        let manifest = DryRunManifest()
        let execution = WaveExecutionPolicy(maxConcurrent: parallelOptions.resolvedMaxConcurrent())

        try await executeBuildPlans(buildPlans, dryRunManifest: manifest)

        if workspaceHygiene.shouldRemoveOrphans {
            try await recordOrphanTeardowns(
                manifest: manifest,
                projectName: projectName,
                composeFile: composeFile
            )
        }

        let hooks = await manifest.makeUpHooks()
        try await ServiceRunner.up(
            layers: layers,
            healthContext: healthContext,
            hooks: hooks,
            execution: execution,
            beforeWave: { index in
                await manifest.setUpWaveIndex(index)
            }
        )
        await manifest.printLines()
    }

    func recordOrphanTeardowns(
        manifest: DryRunManifest,
        projectName: String,
        composeFile: ComposeFile
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
        let orphans = OrphanRemoval.orphans(
            in: discovered,
            composeFile: composeFile,
            policy: .beforeUp(activeProfiles: profileOptions.activeProfileSet)
        )
        for orphan in orphans {
            await manifest.recordTeardown(orphan.name, reason: .orphan)
        }
    }
}
