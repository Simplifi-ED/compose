import Foundation

package enum DownShutdown {
    package struct VolumePurgeContext: Sendable {
        package let composeFile: ComposeFile
        package let fileURLs: [URL]
        package let teardownServiceNames: Set<String>
        package let runningServiceNames: Set<String>

        package init(
            composeFile: ComposeFile,
            fileURLs: [URL],
            teardownServiceNames: Set<String>,
            runningServiceNames: Set<String>
        ) {
            self.composeFile = composeFile
            self.fileURLs = fileURLs
            self.teardownServiceNames = teardownServiceNames
            self.runningServiceNames = runningServiceNames
        }
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
        let paths = collectVolumePurgePaths(context: context)
        let composeDirectory = context.fileURLs[0].deletingLastPathComponent()
        let composeDirectories = context.composeFile.projectRoots(
            for: context.teardownServiceNames.union(context.runningServiceNames),
            defaultDirectory: composeDirectory
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

    package static func collectVolumePurgePaths(context: VolumePurgeContext) -> [String] {
        let composeDirectory = context.fileURLs[0].deletingLastPathComponent()
        return BindMountPurge.collectPurgeablePaths(
            composeFile: context.composeFile,
            composeDirectory: composeDirectory,
            serviceNames: context.teardownServiceNames
        )
    }

    package static func previewVolumePurgePaths(context: VolumePurgeContext) -> [String] {
        let composeDirectory = context.fileURLs[0].deletingLastPathComponent()
        let composeDirectories = context.composeFile.projectRoots(
            for: context.teardownServiceNames.union(context.runningServiceNames),
            defaultDirectory: composeDirectory
        )
        let paths = collectVolumePurgePaths(context: context)
        let runningPaths = BindMountPurge.collectPurgeablePaths(
            composeFile: context.composeFile,
            composeDirectory: composeDirectory,
            serviceNames: context.runningServiceNames
        )
        let protected = BindMountPurge.protectedComposePaths(fileURLs: context.fileURLs)
        return BindMountPurge.plannablePurgePaths(
            paths: paths,
            composeDirectories: composeDirectories,
            protectedPaths: protected,
            pathsInUseByRunningServices: Set(runningPaths)
        )
    }

    package static func resolveShutdownLayers(
        context: ProjectOptions.LabelCommandContext,
        containers: [DiscoveredContainer],
        useOrderedShutdown: Bool
    ) throws -> [[DiscoveredContainer]] {
        if useOrderedShutdown, let composeFile = context.composeFile {
            return try ServicePlanner.shutdownContainerLayers(
                for: composeFile,
                containers: containers
            )
        }
        return [containers]
    }

    static func tearDownContainers(
        context: ProjectOptions.LabelCommandContext,
        containers: [DiscoveredContainer],
        useOrderedShutdown: Bool,
        progress: WaveProgressHandlers?,
        execution: WaveExecutionPolicy = .unlimited,
        machineContext: MachineContext = .applicationSandbox
    ) async throws {
        let layers = try resolveShutdownLayers(
            context: context,
            containers: containers,
            useOrderedShutdown: useOrderedShutdown
        )
        try await ServiceRunner.down(
            layers: layers,
            projectName: context.projectName,
            onRemoved: { print($0) },
            progress: progress,
            execution: execution,
            machineContext: machineContext
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
