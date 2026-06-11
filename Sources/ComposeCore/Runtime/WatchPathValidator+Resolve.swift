import Foundation

extension WatchPathValidator {
    package static func resolveRule(
        serviceName: String,
        ruleIndex: Int,
        rule: ComposeWatchRule,
        composeDirectory: URL
    ) throws -> ResolvedWatchRule {
        try validateRuntimeAction(rule.action)

        let trimmedPath = rule.path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            throw ComposeError.invalidField("develop.watch.path", reason: "path can't be empty")
        }

        let watchRoot = try resolveExistingWatchRoot(trimmedPath, composeDirectory: composeDirectory)

        guard rule.action.requiresTarget else {
            return ResolvedWatchRule(
                serviceName: serviceName,
                ruleIndex: ruleIndex,
                rule: rule,
                watchRoot: watchRoot,
                containerTarget: ""
            )
        }

        guard let target = rule.target else {
            throw ComposeError.invalidField(
                "develop.watch.target",
                reason: "target is required when action is '\(rule.action.rawValue)'"
            )
        }
        let containerTarget = try validateContainerTarget(target)

        return ResolvedWatchRule(
            serviceName: serviceName,
            ruleIndex: ruleIndex,
            rule: rule,
            watchRoot: watchRoot,
            containerTarget: containerTarget
        )
    }

    private static func validateRuntimeAction(_ action: ComposeWatchAction) throws {
        guard !action.isSupportedAtRuntime else { return }
        switch action {
        case .rebuild:
            throw ComposeError.invalidField(
                "develop.watch",
                reason: "action 'rebuild' isn't supported yet (build: is out of scope)"
            )
        case .restart:
            throw ComposeError.invalidField(
                "develop.watch",
                reason: "action 'restart' isn't supported yet; use sync+restart"
            )
        case .syncExec:
            throw ComposeError.invalidField(
                "develop.watch",
                reason: "action 'sync+exec' isn't supported yet"
            )
        case .sync, .syncRestart:
            break
        }
    }

    private static func resolveExistingWatchRoot(_ trimmedPath: String, composeDirectory: URL) throws -> URL {
        let resolvedHost = try BindMountPathResolver.resolveHostPath(
            trimmedPath,
            relativeTo: composeDirectory,
            fieldName: "develop.watch.path"
        )
        let watchRoot: URL = switch resolvedHost {
        case .projectRelative(let url), .absoluteExternal(let url):
            url
        }

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: watchRoot.path, isDirectory: &isDirectory)
        guard exists else {
            throw ComposeError.invalidField(
                "develop.watch.path",
                reason: "path '\(trimmedPath)' doesn't exist on the host"
            )
        }
        return watchRoot
    }
}
