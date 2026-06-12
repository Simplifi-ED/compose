import Foundation

extension DownShutdown {
    private static func teardownScope(
        discovered: [DiscoveredContainer],
        teardownContainers: [DiscoveredContainer]
    ) -> (stillRunning: [DiscoveredContainer], scopedServiceNames: Set<String>) {
        let teardownNames = Set(teardownContainers.map(\.name))
        let stillRunning = discovered.filter { !teardownNames.contains($0.name) }
        let teardownServiceNames = Set(teardownContainers.compactMap(\.serviceName))
        let runningServiceNames = Set(stillRunning.compactMap(\.serviceName))
        return (stillRunning, teardownServiceNames.union(runningServiceNames))
    }

    private struct ResourceRemovalParameters<Plan> {
        let makePlans: (ComposeFile, String, Set<String>) throws -> [Plan]
        let logicalName: (Plan) -> String
        let referencedByService: (ComposeService) -> Set<String>
    }

    private static func resourceRemovalPlans<Plan>(
        context: ProjectOptions.LabelCommandContext,
        discovered: [DiscoveredContainer],
        teardownContainers: [DiscoveredContainer],
        parameters: ResourceRemovalParameters<Plan>
    ) throws -> [Plan] {
        guard let composeFile = context.composeFile else { return [] }

        let (stillRunning, scopedServiceNames) = teardownScope(
            discovered: discovered,
            teardownContainers: teardownContainers
        )
        let allPlans = try parameters.makePlans(composeFile, context.projectName, scopedServiceNames)
        let stillInUse = Set(
            stillRunning
                .compactMap(\.serviceName)
                .flatMap { composeFile.services[$0].map(parameters.referencedByService) ?? [] }
        )
        return allPlans.filter { !stillInUse.contains(parameters.logicalName($0)) }
    }

    /// Project named volumes safe to remove on `down -v`: volumes referenced by
    /// torn-down or still-running services, minus those still needed by running
    /// containers. Empty without a compose file — `-p`-only down can't name
    /// project volumes. Uses the same teardown/running service scope as bind purge.
    package static func volumeRemovalPlans(
        context: ProjectOptions.LabelCommandContext,
        discovered: [DiscoveredContainer],
        teardownContainers: [DiscoveredContainer]
    ) throws -> [VolumePlanning.Plan] {
        try resourceRemovalPlans(
            context: context,
            discovered: discovered,
            teardownContainers: teardownContainers,
            parameters: ResourceRemovalParameters(
                makePlans: VolumePlanning.plans,
                logicalName: \.logicalName,
                referencedByService: VolumePlanning.referencedNamedVolumes(service:)
            )
        )
    }

    /// Project networks safe to remove after teardown: networks referenced by
    /// torn-down or still-running services, minus those still needed by running
    /// containers. Empty without a compose file — `-p`-only down can't name
    /// project networks. Uses the same teardown/running service scope as volume purge.
    package static func networkRemovalPlans(
        context: ProjectOptions.LabelCommandContext,
        discovered: [DiscoveredContainer],
        teardownContainers: [DiscoveredContainer]
    ) throws -> [NetworkPlanning.Plan] {
        try resourceRemovalPlans(
            context: context,
            discovered: discovered,
            teardownContainers: teardownContainers,
            parameters: ResourceRemovalParameters(
                makePlans: NetworkPlanning.plans,
                logicalName: \.logicalName,
                referencedByService: { Set($0.networks) }
            )
        )
    }
}
