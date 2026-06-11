import Foundation

/// Coalesces rapid file-change events before sync (editor multi-write bursts).
package struct WatchDebouncer: Sendable {
    package static let defaultWindow: Duration = .milliseconds(200)

    package struct PendingChange: Sendable, Equatable {
        package let ruleID: String
        package let hostPath: URL
        package let scheduledAt: ContinuousClock.Instant
    }

    private var pending: [String: PendingChange] = [:]
    private let window: Duration

    package init(window: Duration = Self.defaultWindow) {
        self.window = window
    }

    package mutating func schedule(ruleID: String, hostPath: URL, at now: ContinuousClock.Instant) {
        pending[ruleID + "\0" + hostPath.path] = PendingChange(
            ruleID: ruleID,
            hostPath: hostPath,
            scheduledAt: now
        )
    }

    package mutating func drainReady(at now: ContinuousClock.Instant) -> [PendingChange] {
        var ready: [PendingChange] = []
        var remaining: [String: PendingChange] = [:]
        for (key, change) in pending {
            if now - change.scheduledAt >= window {
                ready.append(change)
            } else {
                remaining[key] = change
            }
        }
        pending = remaining
        return ready
    }

    package var isEmpty: Bool {
        pending.isEmpty
    }
}
