import Foundation

extension Down {
    func downOrphanNames(
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

    func resolvedContainers(
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

    func expandedContainersForOrphanRemoval(
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
