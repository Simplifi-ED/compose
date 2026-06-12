import Foundation

public enum BindMountPurge {
    public enum PurgeSkipReason: Equatable, Sendable {
        case protectedComposeFile
        case composeRootDirectory
        case outsideComposeRoot
        case stillInUseByRunningContainer
        case removalFailed(String)
    }

    public struct PurgeResult: Sendable {
        public let removed: [String]
        public let skipped: [(path: String, reason: PurgeSkipReason)]
    }

    /// Collects project-local bind-mount host paths eligible for purge on `down -v`.
    ///
    /// Permissive vs `ServiceRunMapping.volumeFlag`: unparsable or absolute mounts are skipped
    /// silently so purge never fails the whole `down` when the file lists non-purgeable volumes.
    public static func collectPurgeablePaths(
        composeFile: ComposeFile,
        composeDirectory: URL,
        serviceNames: Set<String>
    ) -> [String] {
        var paths: Set<String> = []
        for (serviceName, service) in composeFile.services where serviceNames.contains(serviceName) {
            let serviceDirectory = service.projectDirectory(orDefault: composeDirectory)
            for volume in service.volumes {
                guard let hostPath = try? purgeableHostPath(for: volume, relativeTo: serviceDirectory) else {
                    continue
                }
                paths.insert(hostPath)
            }
        }
        return paths.sorted()
    }

    /// Removes allowlisted bind-mount host paths after containers are stopped.
    public static func purge(
        paths: [String],
        composeDirectory: URL,
        protectedPaths: Set<String> = [],
        pathsInUseByRunningServices: Set<String> = []
    ) -> PurgeResult {
        purge(
            paths: paths,
            composeDirectories: [composeDirectory],
            protectedPaths: protectedPaths,
            pathsInUseByRunningServices: pathsInUseByRunningServices
        )
    }

    public static func purge(
        paths: [String],
        composeDirectories: [URL],
        protectedPaths: Set<String> = [],
        pathsInUseByRunningServices: Set<String> = []
    ) -> PurgeResult {
        let composeRoots = Set(composeDirectories.map {
            $0.standardizedFileURL.resolvingSymlinksInPath().path
        })
        var removed: [String] = []
        var skipped: [(path: String, reason: PurgeSkipReason)] = []

        for path in paths {
            let standardized = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
            let standardizedPath = standardized.path

            if pathsInUseByRunningServices.contains(standardizedPath) {
                skipped.append((path, .stillInUseByRunningContainer))
                continue
            }
            if protectedPaths.contains(standardizedPath) {
                skipped.append((path, .protectedComposeFile))
                continue
            }
            if composeRoots.contains(standardizedPath) {
                skipped.append((path, .composeRootDirectory))
                continue
            }
            let isContained = composeDirectories.contains {
                BindMountPathResolver.isPathContained(standardized, within: $0)
            }
            guard isContained else {
                skipped.append((path, .outsideComposeRoot))
                continue
            }
            guard FileManager.default.fileExists(atPath: standardizedPath) else {
                continue
            }

            do {
                try FileManager.default.removeItem(at: standardized)
                removed.append(standardizedPath)
            } catch {
                skipped.append((path, .removalFailed(error.localizedDescription)))
            }
        }

        return PurgeResult(removed: removed, skipped: skipped)
    }

    /// Paths that would be targeted for removal, excluding structural skips (not filesystem checks).
    public static func plannablePurgePaths(
        paths: [String],
        composeDirectories: [URL],
        protectedPaths: Set<String> = [],
        pathsInUseByRunningServices: Set<String> = []
    ) -> [String] {
        let composeRoots = Set(composeDirectories.map {
            $0.standardizedFileURL.resolvingSymlinksInPath().path
        })
        var planned: [String] = []

        for path in paths {
            let standardized = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
            let standardizedPath = standardized.path

            if pathsInUseByRunningServices.contains(standardizedPath) {
                continue
            }
            if protectedPaths.contains(standardizedPath) {
                continue
            }
            if composeRoots.contains(standardizedPath) {
                continue
            }
            let isContained = composeDirectories.contains {
                BindMountPathResolver.isPathContained(standardized, within: $0)
            }
            guard isContained else { continue }
            planned.append(standardizedPath)
        }

        return planned.sorted()
    }

    public static func protectedComposePaths(fileURLs: [URL]) -> Set<String> {
        Set(fileURLs.map { $0.standardizedFileURL.resolvingSymlinksInPath().path })
    }

    static func warnPurgeSkipped(_ reason: String) {
        fputs("Warning: skipping bind-mount removal; \(reason).\n", stderr)
    }

    static func printPurgeSummary(removed: [String]) {
        guard !removed.isEmpty else { return }
        let pathList = removed.joined(separator: ", ")
        print("Removed \(removed.count) bind-mount path(s): \(pathList)")
    }

    static func warnSkippedPath(path: String, reason: PurgeSkipReason) {
        switch reason {
        case .outsideComposeRoot:
            fputs("Warning: skipped '\(path)': resolves outside the project directory.\n", stderr)
        case .stillInUseByRunningContainer:
            fputs(
                "Warning: skipped '\(path)': still mounted by a running project container.\n",
                stderr
            )
        case .removalFailed(let message):
            fputs("Warning: skipped '\(path)': \(message).\n", stderr)
        case .protectedComposeFile, .composeRootDirectory:
            break
        }
    }

    private static func purgeableHostPath(for volume: String, relativeTo composeDirectory: URL) throws -> String? {
        let spec = try ComposeBindingKeys.parseVolumeSpec(volume)
        guard case .bindMount(let hostPath) = spec.source else {
            return nil
        }
        guard !hostPath.hasPrefix("/") else {
            return nil
        }
        switch try BindMountPathResolver.resolveHostPath(hostPath, relativeTo: composeDirectory) {
        case .projectRelative(let url):
            return url.path
        case .absoluteExternal:
            return nil
        }
    }
}
