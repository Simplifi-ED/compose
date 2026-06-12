import Foundation

extension Down {
    func runDryRun(
        context: ProjectOptions.LabelCommandContext,
        discovered: [DiscoveredContainer],
        containers: [DiscoveredContainer],
        machineContext: MachineContext
    ) async throws {
        let manifest = DryRunManifest(machineName: machineContext.machineName)
        let useOrderedShutdown = context.fileURLs != nil && !projectOptions.hasExplicitProjectName
        let execution = WaveExecutionPolicy(maxConcurrent: parallelOptions.resolvedMaxConcurrent())
        let orphanNames = downOrphanNames(
            discovered: discovered,
            selected: containers,
            context: context
        )
        await manifest.setOrphanNames(orphanNames)

        let layers = try DownShutdown.resolveShutdownLayers(
            context: context,
            containers: containers,
            useOrderedShutdown: useOrderedShutdown
        )
        let teardown = await manifest.makeDownTeardown()
        try await ServiceRunner.orchestrateDown(
            layers: layers,
            onRemoved: nil,
            progress: nil,
            execution: execution,
            teardown: teardown,
            beforeWave: { index in
                await manifest.setDownWaveIndex(index)
            }
        )

        if volumes, let volumePurgeContext = DownShutdown.volumePurgeContext(
            context: context,
            discovered: discovered,
            teardownContainers: containers
        ) {
            let paths = DownShutdown.previewVolumePurgePaths(context: volumePurgeContext)
            await manifest.recordPurge(paths: paths)
        } else if volumes {
            BindMountPurge.warnPurgeSkipped(DownShutdown.volumePurgeSkipReason(context: context))
        }

        if volumes {
            let volumePlans = try DownShutdown.volumeRemovalPlans(
                context: context,
                discovered: discovered,
                teardownContainers: containers
            )
            await manifest.recordVolumeRemovals(names: volumePlans.map(\.runtimeName))
        }

        let networkPlans = try DownShutdown.networkRemovalPlans(
            context: context,
            discovered: discovered,
            teardownContainers: containers
        )
        await manifest.recordNetworkRemovals(names: networkPlans.map(\.runtimeName))

        await manifest.printLines()
    }
}
