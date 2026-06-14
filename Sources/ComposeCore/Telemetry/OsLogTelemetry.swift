import os

// ponytail: loggers + one gate; event strings live at call sites (no per-event wrappers)
package enum OsLogTelemetry {
    static let orchestration = Logger(
        subsystem: OsLogConfiguration.subsystem,
        category: "orchestration"
    )
    static let lifecycle = Logger(
        subsystem: OsLogConfiguration.subsystem,
        category: "lifecycle"
    )
    static let signals = Logger(
        subsystem: OsLogConfiguration.subsystem,
        category: "signals"
    )
    static let volumes = Logger(
        subsystem: OsLogConfiguration.subsystem,
        category: "volumes"
    )
    static let networks = Logger(
        subsystem: OsLogConfiguration.subsystem,
        category: "networks"
    )
    static let build = Logger(
        subsystem: OsLogConfiguration.subsystem,
        category: "build"
    )

    static func enabled(_ body: () -> Void) {
        guard OsLogConfiguration.sessionEnabled else { return }
        body()
    }
}
