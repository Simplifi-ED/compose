import Foundation

/// Session gate for Unified Logging telemetry. Configured once per command entry.
package enum OsLogConfiguration {
    package static let subsystem = "com.simplifi-ed.container-compose"
    package static let environmentVariableName = "COMPOSE_OSLOG"

    // ponytail: single writer at command entry; concurrent readers during orchestration
    nonisolated(unsafe) package static var sessionEnabled = true

    package static func resolve(
        environment: [String: String],
        cliDisabled: Bool,
        dryRun: Bool
    ) -> Bool {
        if cliDisabled || dryRun {
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
        cliNoOslog: Bool = false,
        dryRun: Bool = false,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        sessionEnabled = resolve(
            environment: environment,
            cliDisabled: cliNoOslog,
            dryRun: dryRun
        )
    }

    package static func resetForTesting() {
        sessionEnabled = true
    }
}
