import ContainerResource
import Foundation

package enum ContainerFileSync {
    package typealias CopyIn = ContainerCopyAPI.CopyIn
    package typealias GetContainer = ContainerCopyAPI.GetContainer

    private static let defaultCopyIn: CopyIn = { id, source, destination, mode, createParents in
        try await ContainerCopyAPI.copyIn(
            id: id,
            source: source,
            destination: destination,
            mode: mode,
            createParents: createParents
        )
    }

    private static let defaultGetContainer: GetContainer = { id in
        try await ContainerCopyAPI.get(id: id)
    }

    package static func sync(
        resolved: ResolvedWatchRule,
        hostPath: URL,
        containers: [ProjectContainer],
        projectName: String,
        copyIn: @escaping CopyIn = defaultCopyIn,
        getContainer: @escaping GetContainer = defaultGetContainer
    ) async throws {
        let running = containers.filter { $0.status == .running }
        guard !running.isEmpty else {
            throw ComposeError.serviceNotRunning(
                service: resolved.serviceName,
                state: "not running"
            )
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: hostPath.path, isDirectory: &isDirectory) else {
            return
        }
        let isDir = isDirectory.boolValue

        let destinationBase = try WatchPathValidator.containerDestination(
            watchRoot: resolved.watchRoot,
            containerTarget: resolved.containerTarget,
            changedPath: hostPath
        )

        let relativeDisplay = WatchPathValidator.relativePath(from: resolved.watchRoot, to: hostPath)
            ?? hostPath.lastPathComponent

        try await preflightSyncTargets(
            running: running,
            resolved: resolved,
            projectName: projectName,
            getContainer: getContainer
        )

        let mode: UInt32 = isDir ? 0o755 : 0o644
        for container in running {
            fputs(
                "Syncing \(resolved.serviceName) → \(container.name): \(relativeDisplay)\n",
                stderr
            )
            try await copyIn(
                container.name,
                hostPath.path,
                destinationBase,
                mode,
                true
            )
        }
    }

    private static func preflightSyncTargets(
        running: [ProjectContainer],
        resolved: ResolvedWatchRule,
        projectName: String,
        getContainer: @escaping GetContainer
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for container in running {
                group.addTask {
                    let snapshot = try await getContainer(container.name)
                    try verifySyncTarget(
                        snapshot: snapshot,
                        containerName: container.name,
                        projectName: projectName,
                        serviceName: resolved.serviceName
                    )
                }
            }
            try await group.waitForAll()
        }
    }

    package static func initialSync(
        resolved: ResolvedWatchRule,
        containers: [ProjectContainer],
        projectName: String,
        copyIn: @escaping CopyIn = defaultCopyIn,
        getContainer: @escaping GetContainer = defaultGetContainer
    ) async throws {
        let files = try WatchPathValidator.enumerateSyncableFiles(
            at: resolved.watchRoot,
            ignore: resolved.rule.ignore
        )
        for file in files {
            try await sync(
                resolved: resolved,
                hostPath: file,
                containers: containers,
                projectName: projectName,
                copyIn: copyIn,
                getContainer: getContainer
            )
        }
    }

    package static func verifySyncTarget(
        snapshot: ContainerSnapshot,
        containerName: String,
        projectName: String,
        serviceName: String
    ) throws {
        try ComposeContainerGuard.verifyRunningProjectService(
            snapshot: snapshot,
            containerName: containerName,
            projectName: projectName,
            serviceName: serviceName,
            fieldName: "develop.watch"
        )
    }
}
