import ArgumentParser
import Foundation

public struct Down: AsyncParsableCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        abstract: "Stop and remove containers for the compose project."
    )

    @OptionGroup
    var projectOptions: ProjectOptions

    @OptionGroup
    var progressOptions: ProgressOptions

    @OptionGroup
    var profileOptions: ProfileOptions

    @OptionGroup
    var parallelOptions: ParallelOptions

    @OptionGroup
    var workspaceHygiene: WorkspaceHygieneOptions

    @OptionGroup
    var dryRunOptions: DryRunOptions

    @OptionGroup
    var machineOptions: MachineOptions

    @Flag(
        name: .shortAndLong,
        help: "Remove project-local bind-mount host paths declared in the compose file."
    )
    var volumes = false

    public func run() async throws {
        try parallelOptions.validate()
        var machineContext = try await machineOptions.resolveContext().machineContext
        if machineContext.isMachineMode, !dryRunOptions.isEnabled, !machineContext.isMachineRunning {
            machineContext = try await machineContext.ensureBooted()
        }
        let context = try projectOptions.resolvedLabelCommandContext(
            profileFilterRequested: profileOptions.profileFilterRequested,
            machineContext: machineContext
        )
        let discovered = try await ContainerDiscovery.containers(
            forProject: context.projectName,
            machineContext: machineContext
        )
        var containers = try DownShutdown.filteredContainers(
            discovered: discovered,
            context: context,
            profileFilterRequested: profileOptions.profileFilterRequested,
            activeProfiles: profileOptions.activeProfileSet,
            tearsDownAll: profileOptions.tearsDownAll
        )
        containers = try resolvedContainers(
            discovered: discovered,
            selected: containers,
            context: context
        )

        if dryRunOptions.isEnabled {
            try await runDryRun(
                context: context,
                discovered: discovered,
                containers: containers,
                machineContext: machineContext
            )
            return
        }

        try await executeShutdown(
            context: context,
            discovered: discovered,
            containers: containers,
            machineContext: machineContext
        )
    }

    private func runDryRun(
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

        let networkPlans = try DownShutdown.networkRemovalPlans(
            context: context,
            discovered: discovered,
            teardownContainers: containers
        )
        await manifest.recordNetworkRemovals(names: networkPlans.map(\.runtimeName))

        await manifest.printLines()
    }

    private func downOrphanNames(
        discovered: [DiscoveredContainer],
        selected: [DiscoveredContainer],
        context: ProjectOptions.LabelCommandContext
    ) -> Set<String> {
        guard workspaceHygiene.shouldRemoveOrphans,
              let composeFile = context.composeFile
        else {
            return []
        }
        let orphans = OrphanRemoval.orphans(
            in: discovered,
            composeFile: composeFile,
            policy: .duringDown(
                profileFilterRequested: profileOptions.profileFilterRequested,
                tearsDownAll: profileOptions.tearsDownAll,
                activeProfiles: profileOptions.activeProfileSet
            )
        )
        return Set(orphans.map(\.name))
    }

    private func resolvedContainers(
        discovered: [DiscoveredContainer],
        selected: [DiscoveredContainer],
        context: ProjectOptions.LabelCommandContext
    ) throws -> [DiscoveredContainer] {
        if workspaceHygiene.shouldRemoveOrphans {
            return try expandedContainersForOrphanRemoval(
                discovered: discovered,
                selected: selected,
                context: context
            )
        }
        if let composeFile = context.composeFile {
            DownShutdown.warnUnmappedContainers(in: selected, composeFile: composeFile)
        }
        return selected
    }

    private func executeShutdown(
        context: ProjectOptions.LabelCommandContext,
        discovered: [DiscoveredContainer],
        containers: [DiscoveredContainer],
        machineContext: MachineContext
    ) async throws {
        let useOrderedShutdown = context.fileURLs != nil && !projectOptions.hasExplicitProjectName
        let volumePurgeContext = DownShutdown.volumePurgeContext(
            context: context,
            discovered: discovered,
            teardownContainers: containers
        )
        let displayNames = Dictionary(
            containers.map {
                ($0.name, progressServiceLabel(containerName: $0.name, serviceName: $0.serviceName))
            },
            uniquingKeysWith: { _, last in last }
        )
        let orchestration = makeProgressOrchestration(
            display: progressOptions.resolvedDisplay(),
            phase: .stopping,
            label: { displayNames[$0] ?? $0 }
        )

        let shouldPurgeVolumes = volumes
        let execution = WaveExecutionPolicy(maxConcurrent: parallelOptions.resolvedMaxConcurrent())
        try await runOrchestrationCommand(
            lines: orchestration.lines,
            interruptedMessage: "Shutdown interrupted. Some containers may still be running."
        ) {
            try await DownShutdown.tearDownContainers(
                context: context,
                containers: containers,
                useOrderedShutdown: useOrderedShutdown,
                progress: orchestration.handlers,
                execution: execution,
                machineContext: machineContext
            )
            if shouldPurgeVolumes, let volumePurgeContext {
                DownShutdown.purgeVolumes(context: volumePurgeContext)
            } else if shouldPurgeVolumes {
                BindMountPurge.warnPurgeSkipped(DownShutdown.volumePurgeSkipReason(context: context))
            }
            await NetworkRunner.removeProjectNetworks(
                try DownShutdown.networkRemovalPlans(
                    context: context,
                    discovered: discovered,
                    teardownContainers: containers
                ),
                projectName: context.projectName,
                machineContext: machineContext
            )
            ComposeFileStaging.removeProjectStaging(projectName: context.projectName)
        }
    }

    private func expandedContainersForOrphanRemoval(
        discovered: [DiscoveredContainer],
        selected: [DiscoveredContainer],
        context: ProjectOptions.LabelCommandContext
    ) throws -> [DiscoveredContainer] {
        guard let composeFile = context.composeFile else {
            WorkspaceHygieneOutput.warnOrphanRemovalSkipped("compose file required")
            return selected
        }

        let orphans = OrphanRemoval.orphans(
            in: discovered,
            composeFile: composeFile,
            policy: .duringDown(
                profileFilterRequested: profileOptions.profileFilterRequested,
                tearsDownAll: profileOptions.tearsDownAll,
                activeProfiles: profileOptions.activeProfileSet
            )
        )
        return OrphanRemoval.mergingContainers(selected, with: orphans)
    }
}
