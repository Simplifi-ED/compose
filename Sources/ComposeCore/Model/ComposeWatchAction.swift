import Foundation

public enum ComposeWatchAction: String, Sendable, Equatable, CaseIterable {
    case sync
    case syncRestart = "sync+restart"
    case rebuild
    case restart
    case syncExec = "sync+exec"

    package var requiresTarget: Bool {
        switch self {
        case .sync, .syncRestart, .syncExec:
            return true
        case .rebuild, .restart:
            return false
        }
    }

    package var isSupportedAtRuntime: Bool {
        switch self {
        case .sync, .syncRestart:
            return true
        case .rebuild, .restart, .syncExec:
            return false
        }
    }

    package static func parse(_ raw: String) throws -> ComposeWatchAction {
        guard let action = ComposeWatchAction(rawValue: raw) else {
            throw ComposeError.invalidField(
                "develop.watch.action",
                reason: "expected sync, sync+restart, or rebuild (got '\(raw)')"
            )
        }
        return action
    }
}
