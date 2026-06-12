import Foundation

extension Down {
    struct ContainerResolution: Sendable {
        let containers: [DiscoveredContainer]
        let orphanNames: Set<String>
    }

    func resolveContainersForShutdown(
        discovered: [DiscoveredContainer],
        selected: [DiscoveredContainer],
        context: ProjectOptions.LabelCommandContext
    ) throws -> ContainerResolution {
        if workspaceHygiene.shouldRemoveOrphans {
            guard let composeFile = context.composeFile else {
                WorkspaceHygieneOutput.warnOrphanRemovalSkipped("compose file required")
                return ContainerResolution(containers: selected, orphanNames: [])
            }
            let policy = OrphanRemoval.Policy.duringDown(
                profileFilterRequested: profileOptions.profileFilterRequested,
                tearsDownAll: profileOptions.tearsDownAll,
                activeProfiles: profileOptions.activeProfileSet
            )
            let orphans = OrphanRemoval.orphans(
                in: discovered,
                composeFile: composeFile,
                policy: policy
            )
            return ContainerResolution(
                containers: OrphanRemoval.mergingContainers(selected, with: orphans),
                orphanNames: Set(orphans.map(\.name))
            )
        }
        if let composeFile = context.composeFile {
            DownShutdown.warnUnmappedContainers(in: selected, composeFile: composeFile)
        }
        return ContainerResolution(containers: selected, orphanNames: [])
    }
}
