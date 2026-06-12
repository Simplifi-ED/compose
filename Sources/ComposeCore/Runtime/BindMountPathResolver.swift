import Foundation

package enum BindMountPathResolver {
    package enum ResolvedHostPath: Equatable {
        case projectRelative(URL)
        case absoluteExternal(URL)
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
