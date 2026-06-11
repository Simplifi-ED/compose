import Foundation

package enum BindMountPathResolver {
    package enum ResolvedHostPath: Equatable {
        case projectRelative(URL)
        case absoluteExternal(URL)
    }

    static func parseVolumeSpec(_ volume: String) throws -> (hostPath: String, containerPath: String) {
        let trimmed = volume.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ComposeError.unsupportedVolume(volume)
        }

        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count == 3 {
            throw ComposeError.unsupportedVolumeOption(volume)
        }
        guard parts.count == 2 else {
            throw ComposeError.unsupportedVolume(volume)
        }

        let hostPath = String(parts[0])
        let containerPath = String(parts[1])

        guard !hostPath.isEmpty, !containerPath.isEmpty else {
            throw ComposeError.unsupportedVolume(volume)
        }
        guard containerPath.hasPrefix("/") else {
            throw ComposeError.unsupportedVolume(volume)
        }

        let isBindMountSource = hostPath.contains("/") || hostPath == "." || hostPath == ".."
        guard isBindMountSource else {
            throw ComposeError.unsupportedNamedVolume(volume)
        }

        return (hostPath, containerPath)
    }

    package static func resolveHostPath(
        _ hostPath: String,
        relativeTo composeDirectory: URL,
        fieldName: String = "volumes"
    ) throws -> ResolvedHostPath {
        if hostPath.hasPrefix("/") {
            return .absoluteExternal(
                URL(fileURLWithPath: hostPath).standardizedFileURL.resolvingSymlinksInPath()
            )
        }

        let resolvedHostURL = composeDirectory.appendingPathComponent(hostPath)
        let standardized = resolvedHostURL.standardizedFileURL.resolvingSymlinksInPath()
        let composeRoot = composeDirectory.standardizedFileURL.resolvingSymlinksInPath()
        guard isPathContained(standardized, within: composeRoot) else {
            throw ComposeError.invalidField(
                fieldName,
                reason: "host path '\(hostPath)' resolves outside the compose file directory. "
                    + "Use a path within the project or an absolute host path."
            )
        }
        return .projectRelative(standardized)
    }

    static func isPathContained(_ path: URL, within root: URL) -> Bool {
        let resolvedPath = path.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        if resolvedPath == rootPath {
            return true
        }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return resolvedPath.hasPrefix(prefix)
    }
}
