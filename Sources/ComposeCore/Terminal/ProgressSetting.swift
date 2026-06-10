import Foundation

/// User-selected `--progress` value before terminal detection.
package enum ProgressSetting: String, CaseIterable, Sendable {
    /// Detect from stderr (spinner on a TTY, plain text otherwise).
    case auto
    /// Newline-separated status lines without escape sequences.
    case plain
    /// No orchestration progress on stderr (runtime image pulls may still print).
    case none
}

/// Resolved rendering style for orchestration progress on stderr.
package enum ProgressDisplay: Equatable, Sendable {
    case interactive
    case plain
    case silent

    package static func resolve(
        setting: ProgressSetting,
        terminalMode: TerminalMode
    ) -> ProgressDisplay {
        switch setting {
        case .none:
            return .silent
        case .plain:
            return .plain
        case .auto:
            switch terminalMode {
            case .interactive:
                return .interactive
            case .plain, .pipe:
                return .plain
            }
        }
    }

    package static func resolve(
        setting: ProgressSetting,
        isTTY: Bool,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> ProgressDisplay {
        resolve(setting: setting, terminalMode: TerminalMode.resolve(isTTY: isTTY, environment: environment))
    }

    /// Resolves against the live standard error file descriptor.
    package static func resolve(
        setting: ProgressSetting,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> ProgressDisplay {
        resolve(
            setting: setting,
            terminalMode: TerminalMode.resolve(
                fileDescriptor: FileHandle.standardError.fileDescriptor,
                environment: environment
            )
        )
    }
}
