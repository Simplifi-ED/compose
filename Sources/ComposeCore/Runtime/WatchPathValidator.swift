import Foundation

/// Resolved watch rule with absolute host path and validated container target prefix.
package struct ResolvedWatchRule: Sendable, Equatable {
    package let serviceName: String
    package let ruleIndex: Int
    package let rule: ComposeWatchRule
    package let watchRoot: URL
    package let containerTarget: String

    package var ruleID: String {
        "\(serviceName)#\(ruleIndex)"
    }
}

package enum WatchPathValidator {
    package static func validateRules(
        serviceName: String,
        develop: ComposeDevelop?,
        composeDirectory: URL
    ) throws -> [ResolvedWatchRule] {
        guard let develop, !develop.watch.isEmpty else { return [] }
        return try develop.watch.enumerated().map { index, rule in
            try resolveRule(
                serviceName: serviceName,
                ruleIndex: index,
                rule: rule,
                composeDirectory: composeDirectory
            )
        }
    }

    package static func validateContainerTarget(_ target: String) throws -> String {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else {
            throw ComposeError.invalidField(
                "develop.watch.target",
                reason: "target must be an absolute in-container path starting with '/'"
            )
        }
        let components = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        if components.contains("..") {
            throw ComposeError.invalidField(
                "develop.watch.target",
                reason: "target must not contain '..' segments"
            )
        }
        if trimmed.hasSuffix("/") && trimmed != "/" {
            return String(trimmed.dropLast())
        }
        return trimmed
    }

    /// Maps a changed host file to its in-container destination per compose-spec path/target rules.
    package static func containerDestination(
        watchRoot: URL,
        containerTarget: String,
        changedPath: URL
    ) throws -> String {
        let rootPath = watchRoot.standardizedFileURL.path
        let changedPathStandard = changedPath.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard changedPathStandard == rootPath || changedPathStandard.hasPrefix(prefix) else {
            throw ComposeError.invalidField(
                "develop.watch",
                reason: "changed path is outside the watch root"
            )
        }

        let relative: String
        if changedPathStandard == rootPath {
            relative = ""
        } else {
            relative = String(changedPathStandard.dropFirst(prefix.count))
        }

        if relative.isEmpty {
            return containerTarget
        }
        return containerTarget + "/" + relative
    }

    package static func isIgnored(relativePath: String, patterns: [String]) -> Bool {
        guard !patterns.isEmpty else { return false }
        let normalized = relativePath.replacingOccurrences(of: "\\", with: "/")
        return patterns.contains { matchesIgnorePattern(normalized, pattern: $0) }
    }

    package static func relativePath(from watchRoot: URL, to changedPath: URL) -> String? {
        let rootPath = watchRoot.standardizedFileURL.path
        let changedPathStandard = changedPath.standardizedFileURL.path
        if changedPathStandard == rootPath {
            return ""
        }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard changedPathStandard.hasPrefix(prefix) else { return nil }
        return String(changedPathStandard.dropFirst(prefix.count))
    }

    package static func enumerateSyncableFiles(at watchRoot: URL, ignore: [String]) throws -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: watchRoot.path, isDirectory: &isDirectory) else {
            return []
        }
        if !isDirectory.boolValue {
            return [watchRoot]
        }

        guard let enumerator = FileManager.default.enumerator(
            at: watchRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let url as URL in enumerator {
            guard let relative = relativePath(from: watchRoot, to: url) else { continue }
            if isIgnored(relativePath: relative, patterns: ignore) {
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true {
                files.append(url)
            }
        }
        return files
    }

    private static func matchesIgnorePattern(_ relativePath: String, pattern: String) -> Bool {
        var normalizedPattern = pattern.replacingOccurrences(of: "\\", with: "/")
        if normalizedPattern.hasPrefix("**/") {
            let suffix = String(normalizedPattern.dropFirst(3))
            return relativePath.split(separator: "/").contains { $0 == Substring(suffix) }
                || relativePath.hasSuffix("/" + suffix)
                || relativePath == suffix
        }
        if normalizedPattern.hasSuffix("/") {
            normalizedPattern = String(normalizedPattern.dropLast())
        }
        if relativePath == normalizedPattern {
            return true
        }
        let prefix = normalizedPattern.hasSuffix("/") ? normalizedPattern : normalizedPattern + "/"
        return relativePath.hasPrefix(prefix)
            || relativePath.split(separator: "/").contains { $0 == Substring(normalizedPattern) }
    }
}
