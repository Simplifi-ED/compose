import Foundation

package enum DownShutdown {
    package struct VolumePurgeContext: Sendable {
        let composeFile: ComposeFile
        let fileURLs: [URL]
        let teardownServiceNames: Set<String>
        let runningServiceNames: Set<String>
    }

    static func filteredContainers(
        discovered: [DiscoveredContainer],
        context: ProjectOptions.LabelCommandContext,
        profileFilterRequested: Bool,
        activeProfiles: Set<String>,
        tearsDownAll: Bool
    ) throws -> [DiscoveredContainer] {
        guard profileFilterRequested else { return discovered }
        let serviceFilter = try ProfileFilter.downServiceFilter(
            composeFile: context.composeFile,
            activeProfiles: activeProfiles,
            tearsDownAll: tearsDownAll
        )
        return ProjectStatus.filteredDiscoveredContainers(from: discovered, filter: serviceFilter)
    }

    package static func volumePurgeSkipReason(
        context: ProjectOptions.LabelCommandContext
    ) -> String {
        if context.composeFile == nil {
            return "compose file required"
        }
        if context.fileURLs == nil || context.fileURLs?.isEmpty == true {
            return "compose file path required"
        }
        return "volume purge unavailable"
    }

    package static func volumePurgeContext(
        context: ProjectOptions.LabelCommandContext,
        discovered: [DiscoveredContainer],
        teardownContainers: [DiscoveredContainer]
    ) -> VolumePurgeContext? {
        guard let composeFile = context.composeFile,
              let fileURLs = context.fileURLs,
              !fileURLs.isEmpty
        else {
            return nil
        }

        let teardownNames = Set(teardownContainers.map(\.name))
        let stillRunning = discovered.filter { !teardownNames.contains($0.name) }
        let teardownServiceNames = Set(teardownContainers.compactMap(\.serviceName))
        let runningServiceNames = Set(stillRunning.compactMap(\.serviceName))

        return VolumePurgeContext(
            composeFile: composeFile,
            fileURLs: fileURLs,
            teardownServiceNames: teardownServiceNames,
            runningServiceNames: runningServiceNames
        )
    }

    static func purgeVolumes(context: VolumePurgeContext) {
        let composeDirectory = context.fileURLs[0].deletingLastPathComponent()
        let composeDirectories = context.composeFile.projectRoots(
            for: context.teardownServiceNames.union(context.runningServiceNames),
            defaultDirectory: composeDirectory
        )
        let paths = BindMountPurge.collectPurgeablePaths(
            composeFile: context.composeFile,
            composeDirectory: composeDirectory,
            serviceNames: context.teardownServiceNames
        )
        let runningPaths = BindMountPurge.collectPurgeablePaths(
            composeFile: context.composeFile,
            composeDirectory: composeDirectory,
            serviceNames: context.runningServiceNames
        )
        let protected = BindMountPurge.protectedComposePaths(fileURLs: context.fileURLs)
        let result = BindMountPurge.purge(
            paths: paths,
            composeDirectories: composeDirectories,
            protectedPaths: protected,
            pathsInUseByRunningServices: Set(runningPaths)
        )
        for skipped in result.skipped {
            BindMountPurge.warnSkippedPath(path: skipped.path, reason: skipped.reason)
        }
        BindMountPurge.printPurgeSummary(removed: result.removed)
    }

    static func tearDownContainers(
        context: ProjectOptions.LabelCommandContext,
        containers: [DiscoveredContainer],
        useOrderedShutdown: Bool,
        progress: WaveProgressHandlers?,
        execution: WaveExecutionPolicy = .unlimited
    ) async throws {
        if useOrderedShutdown, let composeFile = context.composeFile {
            let layers = try ServicePlanner.shutdownContainerLayers(
                for: composeFile,
                containers: containers
            )
            try await ServiceRunner.down(
                layers: layers,
                projectName: context.projectName,
                onRemoved: { print($0) },
                progress: progress,
                execution: execution
            )
            return
        }
        try await ServiceRunner.down(
            containers: containers,
            projectName: context.projectName,
            onRemoved: { print($0) },
            progress: progress,
            execution: execution
        )
    }

    static func warnUnmappedContainers(
        in containers: [DiscoveredContainer],
        composeFile: ComposeFile
    ) {
        let unmapped = ServicePlanner.unmappedContainers(in: containers, composeFile: composeFile)
        guard !unmapped.isEmpty else { return }
        let names = unmapped.map(\.name).joined(separator: ", ")
        fputs(
            """
            Warning: \(unmapped.count) container(s) without a compose service mapping (\(names)) \
            stop last; depends_on order may not apply to them. \
            Pass --remove-orphans on up to remove them before startup.\n
            """,
            stderr
        )
    }
}
