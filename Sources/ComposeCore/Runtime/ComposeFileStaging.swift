import Foundation

package enum ComposeFileStaging {
    private static let rootFolderName = "container-compose"
    private static let configFolderName = ".config"

    package static func stagingRoot() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(configFolderName, isDirectory: true)
            .appendingPathComponent(rootFolderName, isDirectory: true)
    }

    package static func projectRoot(projectName: String) -> URL {
        stagingRoot()
            .appendingPathComponent(projectName, isDirectory: true)
    }

    package static func containerDirectory(projectName: String, containerName: String) -> URL {
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
        do {
            return try mounts.map { mount in
                let stagedURL = directory.appendingPathComponent(stagedFileName(for: mount))
                try copySource(mount: mount, to: stagedURL)
                return StagedMount(
                    containerTarget: mount.containerTarget,
                    hostPath: stagedURL.path
                )
            }
        } catch {
            removeContainerStaging(projectName: projectName, containerName: containerName)
            throw error
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
        try insertVolumeArguments(into: &runArguments, image: plan.image, volumeArgs: volumeArgs)
        return runArguments
    }

    static func volumeArguments(for stagedMounts: [StagedMount]) -> [String] {
        stagedMounts.flatMap { staged in
            [
                "-v",
                readOnlyVolumeFlag(
                    hostPath: staged.hostPath,
                    containerPath: staged.containerTarget
                )
            ]
        }
    }

    static func insertVolumeArguments(
        into runArguments: inout [String],
        image: String,
        volumeArgs: [String]
    ) throws {
        guard !volumeArgs.isEmpty else { return }
        guard let imageIndex = runArguments.firstIndex(of: image) else {
            throw ComposeError.invalidField(
                "run arguments",
                reason: "image token '\(image)' not found; volume mounts must appear before the image"
            )
        }
        runArguments.insert(contentsOf: volumeArgs, at: imageIndex)
    }

    package static func removeContainerStaging(projectName: String, containerName: String) {
        let directory = containerDirectory(projectName: projectName, containerName: containerName)
        try? FileManager.default.removeItem(at: directory)
        pruneEmptyParents(startingAt: directory.deletingLastPathComponent())
    }

    package static func removeProjectStaging(projectName: String) {
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

    package static func readOnlyVolumeFlag(hostPath: String, containerPath: String) -> String {
        "\(hostPath):\(containerPath):ro"
    }

    private static func copySource(mount: PlannedFileMount, to destination: URL) throws {
        let source = try ComposeFileMountResolver.verifiedSourceFile(
            relativePath: mount.sourceRelativePath,
            resolutionRoot: mount.resolutionRoot,
            kind: mount.kind
        )
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
        let permissions: Int
        switch mount.kind {
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
        let stagingRootPath = stagingRoot().path
        while current.path.hasPrefix(stagingRootPath) {
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
