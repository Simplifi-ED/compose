import Foundation

/// How output should be rendered for the current terminal.
///
/// Resolution order:
/// 1. Not a TTY → `.pipe` (redirected output must stay machine-safe; no ANSI)
/// 2. `NO_COLOR` set and non-empty → `.plain` (https://no-color.org)
/// 3. `CI` truthy → `.plain`
/// 4. Otherwise → `.interactive`
package enum TerminalMode: Equatable, Sendable {
    /// TTY attached; ANSI colors and in-place redraw are allowed.
    case interactive
    /// TTY attached, but colors are disabled (`NO_COLOR` or `CI`).
    case plain
    /// Output is redirected (not a TTY); no escape sequences at all.
    case pipe

    package static func resolve(
        isTTY: Bool,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> TerminalMode {
        guard isTTY else { return .pipe }
        if isEnvironmentColorDisabled(environment) || isEnvironmentCI(environment) {
            return .plain
        }
        return .interactive
    }

    /// Resolves against the live standard output file descriptor.
    package static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> TerminalMode {
        resolve(isTTY: isatty(FileHandle.standardOutput.fileDescriptor) == 1, environment: environment)
    }

    /// `NO_COLOR` disables color when present with any non-empty value.
    package static func isEnvironmentColorDisabled(_ environment: [String: String]) -> Bool {
        guard let value = environment["NO_COLOR"] else { return false }
        return !value.isEmpty
    }

    /// `CI` is truthy when set to anything other than an empty string, "false", or "0".
    package static func isEnvironmentCI(_ environment: [String: String]) -> Bool {
        guard let value = environment["CI"] else { return false }
        let lowered = value.lowercased()
        return !lowered.isEmpty && lowered != "false" && lowered != "0"
    }
}
