import Foundation

public enum ComposeFileMountKind: String, Sendable, Equatable, CaseIterable {
    case config
    case secret

    public var rootFieldName: String {
        switch self {
        case .config: "configs"
        case .secret: "secrets"
        }
    }

    public var defaultTargetPrefix: String {
        switch self {
        case .config: "/run/configs/"
        case .secret: "/run/secrets/"
        }
    }

    public func defaultTarget(for sourceName: String) -> String {
        defaultTargetPrefix + sourceName
    }

    public func resolvedTarget(sourceName: String, explicitTarget: String?) -> String {
        guard let explicitTarget, !explicitTarget.isEmpty else {
            return defaultTarget(for: sourceName)
        }
        if explicitTarget.hasPrefix("/") {
            return explicitTarget
        }
        return defaultTargetPrefix + explicitTarget
    }
}
