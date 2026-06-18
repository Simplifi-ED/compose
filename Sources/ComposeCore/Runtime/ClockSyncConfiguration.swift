import Foundation

/// Session gate for guest clock sync after macOS wake. Configured once per command entry.
package enum ClockSyncConfiguration {
    package static let environmentVariableName = "COMPOSE_CLOCK_SYNC"

    // ponytail: single writer at command entry; concurrent readers during orchestration
    nonisolated(unsafe) package static var sessionEnabled = true

    package static func resolve(
        environment: [String: String],
        cliDisabled: Bool
    ) -> Bool {
        if cliDisabled {
            return false
        }
        guard let raw = environment[environmentVariableName] else {
            return true
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty {
            return true
        }
        return trimmed != "0" && trimmed != "false" && trimmed != "no"
    }

    package static func apply(
        cliNoClockSync: Bool = false,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        sessionEnabled = resolve(environment: environment, cliDisabled: cliNoClockSync)
    }

    package static func resetForTesting() {
        sessionEnabled = true
    }
}
