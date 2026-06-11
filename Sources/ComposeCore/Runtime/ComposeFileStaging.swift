import Foundation

package enum ComposeFileStaging {
    private static let rootFolderName = "container-compose"

    static func projectRoot(projectName: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(rootFolderName, isDirectory: true)
            .appendingPathComponent(projectName, isDirectory: true)
    }

    static func containerDirectory(projectName: String, containerName: String) -> URL {
        projectRoot(projectName: projectName)
            .appendingPathComponent(containerName, isDirectory: true)
    }

    struct StagedMount: Sendable, Equatable {
        let containerTarget: String
        let hostPath: String
    }

    static func stage(
        mounts: [PlannedFileMount],
        projectName: String,
        containerName: String
    ) throws -> [StagedMount] {
        let directory = containerDirectory(projectName: projectName, containerName: containerName)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: 0o700)]
        )
        return try mounts.map { mount in
            let stagedURL = directory.appendingPathComponent(stagedFileName(for: mount))
            try copySource(at: mount.sourcePath, to: stagedURL, kind: mount.kind)
            return StagedMount(
                containerTarget: mount.containerTarget,
                hostPath: stagedURL.path
            )
        }
    }

    package static func preparedRunArguments(for plan: ServicePlan) throws -> [String] {
        var runArguments = plan.runArguments
        let staged = try stage(
            mounts: plan.fileMounts,
            projectName: plan.projectName,
            containerName: plan.name
        )
        let volumeArgs = volumeArguments(for: staged)
        insertVolumeArguments(into: &runArguments, image: plan.image, volumeArgs: volumeArgs)
        return runArguments
    }

    static func volumeArguments(for stagedMounts: [StagedMount]) -> [String] {
        stagedMounts.flatMap { staged in
            [
                "-v",
                ComposeFileMountResolver.readOnlyVolumeFlag(
                    hostPath: staged.hostPath,
                    containerPath: staged.containerTarget
                )
            ]
        }
    }

    static func insertVolumeArguments(into runArguments: inout [String], image: String, volumeArgs: [String]) {
        guard !volumeArgs.isEmpty else { return }
        if let imageIndex = runArguments.firstIndex(of: image) {
            runArguments.insert(contentsOf: volumeArgs, at: imageIndex)
        } else {
            runArguments.insert(contentsOf: volumeArgs, at: runArguments.count)
        }
    }

    static func removeContainerStaging(projectName: String, containerName: String) {
        let directory = containerDirectory(projectName: projectName, containerName: containerName)
        try? FileManager.default.removeItem(at: directory)
        pruneEmptyParents(startingAt: directory.deletingLastPathComponent())
    }

    static func removeProjectStaging(projectName: String) {
        let directory = projectRoot(projectName: projectName)
        try? FileManager.default.removeItem(at: directory)
        pruneEmptyParents(startingAt: directory.deletingLastPathComponent())
    }

    private static func stagedFileName(for mount: PlannedFileMount) -> String {
        switch mount.kind {
        case .config:
            "config-\(mount.definitionName)"
        case .secret:
            "secret-\(mount.definitionName)"
        }
    }

    private static func copySource(at source: URL, to destination: URL, kind: ComposeFileMountKind) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
        let permissions: Int
        switch kind {
        case .secret:
            permissions = 0o600
        case .config:
            permissions = 0o644
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: permissions)],
            ofItemAtPath: destination.path
        )
    }

    private static func pruneEmptyParents(startingAt url: URL) {
        var current = url
        let tmpRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(rootFolderName, isDirectory: true)
        while current.path.hasPrefix(tmpRoot.path) {
            guard let contents = try? FileManager.default.contentsOfDirectory(atPath: current.path),
                  contents.isEmpty
            else {
                break
            }
            try? FileManager.default.removeItem(at: current)
            current = current.deletingLastPathComponent()
        }
    }
}
