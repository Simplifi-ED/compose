import Foundation

extension Down {
    func runDryRun(
        context: ProjectOptions.LabelCommandContext,
        discovered: [DiscoveredContainer],
        containers: [DiscoveredContainer],
        orphanNames: Set<String>,
        machineContext: MachineContext
    ) async throws {
        let manifest = DryRunManifest(machineName: machineContext.machineName)
        let useOrderedShutdown = context.fileURLs != nil
        let execution = WaveExecutionPolicy(maxConcurrent: parallelOptions.resolvedMaxConcurrent())
        await manifest.setOrphanNames(orphanNames)

        try await recordDryRunTeardown(
            manifest: manifest,
            context: context,
            containers: containers,
            useOrderedShutdown: useOrderedShutdown,
            execution: execution
        )

        try await recordVolumeDryRun(
            manifest: manifest,
            context: context,
            discovered: discovered,
            containers: containers
        )

        if trim {
            try await recordTrimDryRun(
                manifest: manifest,
                context: context,
                discovered: discovered,
                containers: containers,
                machineContext: machineContext
            )
        }

        let networkPlans = try DownShutdown.networkRemovalPlans(
            context: context,
            discovered: discovered,
            teardownContainers: containers
        )
        await manifest.recordNetworkRemovals(names: networkPlans.map(\.runtimeName))
        await HostDNSMapping.removeProjectMappings(
            projectName: context.projectName,
            firstComposeFileURL: context.fileURLs?.first,
            dryRunManifest: manifest
        )

        await manifest.printLines()
    }
}
