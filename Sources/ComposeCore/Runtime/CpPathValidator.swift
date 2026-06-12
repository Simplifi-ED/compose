import Foundation

package enum CpPathValidator {
    package enum HostPathRole: Sendable {
        case source
        case destination
    }

    package struct ResolvedHostPath: Sendable, Equatable {
        package let path: String
    }

    package static func validateContainerPath(_ path: String) throws -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else {
            throw ComposeError.invalidCpPath(
                reason: "container path must be absolute (start with /)"
            )
        }
        let components = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        if components.contains("..") {
            throw ComposeError.invalidCpPath(
                reason: "container path must not contain '..' segments"
            )
        }
        return trimmed
    }

    package static func resolveHostPath(
        _ rawPath: String,
        role: HostPathRole
    ) throws -> ResolvedHostPath {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ComposeError.invalidCpPath(reason: "host path is empty")
        }

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .standardizedFileURL
            .resolvingSymlinksInPath()

        let resolvedURL: URL
        if trimmed.hasPrefix("/") {
            resolvedURL = URL(fileURLWithPath: trimmed)
                .standardizedFileURL
                .resolvingSymlinksInPath()
            if !BindMountPathResolver.isPathContained(resolvedURL, within: cwd) {
                fputs(
                    "Warning: absolute host path '\(trimmed)' is outside the current directory.\n",
                    stderr
                )
            }
        } else {
            resolvedURL = cwd.appendingPathComponent(trimmed)
                .standardizedFileURL
                .resolvingSymlinksInPath()
            guard BindMountPathResolver.isPathContained(resolvedURL, within: cwd) else {
                throw ComposeError.cpHostPathOutsideCWD(path: trimmed)
            }
        }

        if role == .source {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: resolvedURL.path, isDirectory: &isDirectory) else {
                throw ComposeError.cpSourceNotFound(path: trimmed)
            }
        }

        return ResolvedHostPath(path: resolvedURL.path)
    }
}
