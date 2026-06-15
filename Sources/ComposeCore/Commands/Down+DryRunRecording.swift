import Foundation

extension Down {
    func recordDryRunTeardown(
        manifest: DryRunManifest,
        context: ProjectOptions.LabelCommandContext,
        containers: [DiscoveredContainer],
        useOrderedShutdown: Bool,
        execution: WaveExecutionPolicy
    ) async throws {
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
    }

    func recordVolumeDryRun(
        manifest: DryRunManifest,
        context: ProjectOptions.LabelCommandContext,
        discovered: [DiscoveredContainer],
        containers: [DiscoveredContainer]
    ) async throws {
        guard volumes else { return }
        if let volumePurgeContext = DownShutdown.volumePurgeContext(
            context: context,
            discovered: discovered,
            teardownContainers: containers
        ) {
            let paths = DownShutdown.previewVolumePurgePaths(context: volumePurgeContext)
            await manifest.recordPurge(paths: paths)
        } else {
            BindMountPurge.warnPurgeSkipped(DownShutdown.volumePurgeSkipReason(context: context))
        }
        let volumePlans = try DownShutdown.volumeRemovalPlans(
            context: context,
            discovered: discovered,
            teardownContainers: containers
        )
        await manifest.recordVolumeRemovals(names: volumePlans.map(\.runtimeName))
    }

    func recordTrimDryRun(
        manifest: DryRunManifest,
        context: ProjectOptions.LabelCommandContext,
        discovered: [DiscoveredContainer],
        containers: [DiscoveredContainer],
        machineContext: MachineContext
    ) async throws {
        let volumeNames: [String]
        if volumes {
            volumeNames = try DownShutdown.volumeRemovalPlans(
                context: context,
                discovered: discovered,
                teardownContainers: containers
            ).map(\.runtimeName)
        } else {
            volumeNames = []
        }
        await manifest.recordDiskTrims(
            containerNames: containers.map(\.name),
            volumeNames: volumeNames,
            machineName: machineContext.machineName
        )
    }
}
