import Foundation

extension Up {
    struct DryRunInput: Sendable {
        let projectName: String
        let composeFile: ComposeFile
        let layers: [[ServicePlan]]
        let healthContext: HealthWaitContext
        let buildPlans: [BuildRunner.Plan]
        let machineContext: MachineContext
    }

    func runDryRun(_ input: DryRunInput) async throws {
        let manifest = DryRunManifest(machineName: input.machineContext.machineName)
        let execution = WaveExecutionPolicy(maxConcurrent: parallelOptions.resolvedMaxConcurrent())

        try await executeBuildPlans(input.buildPlans, dryRunManifest: manifest)

        if workspaceHygiene.shouldRemoveOrphans {
            try await recordOrphanTeardowns(
                manifest: manifest,
                projectName: input.projectName,
                composeFile: input.composeFile,
                machineContext: input.machineContext
            )
        }

        let hooks = await manifest.makeUpHooks(machineContext: input.machineContext)
        try await ServiceRunner.up(
            layers: input.layers,
            healthContext: input.healthContext,
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
        composeFile: ComposeFile,
        machineContext: MachineContext
    ) async throws {
        let discovered: [DiscoveredContainer]
        do {
            discovered = try await ContainerDiscovery.containers(
                forProject: projectName,
                machineContext: machineContext
            )
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
