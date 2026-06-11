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
    var workspaceHygiene: WorkspaceHygieneOptions

    @Flag(
        name: .shortAndLong,
        help: "Remove project-local bind-mount host paths declared in the compose file."
    )
    var volumes = false

    public func run() async throws {
        let context = try projectOptions.resolvedLabelCommandContext(
            profileFilterRequested: profileOptions.profileFilterRequested
        )
        let discovered = try await ContainerDiscovery.containers(forProject: context.projectName)
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

        try await executeShutdown(
            context: context,
            discovered: discovered,
            containers: containers
        )
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
        containers: [DiscoveredContainer]
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
        try await runOrchestrationCommand(
            lines: orchestration.lines,
            interruptedMessage: "Shutdown interrupted. Some containers may still be running."
        ) {
            try await DownShutdown.tearDownContainers(
                context: context,
                containers: containers,
                useOrderedShutdown: useOrderedShutdown,
                progress: orchestration.handlers
            )
            if shouldPurgeVolumes, let volumePurgeContext {
                DownShutdown.purgeVolumes(context: volumePurgeContext)
            } else if shouldPurgeVolumes {
                BindMountPurge.warnPurgeSkipped("compose file required")
            }
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
