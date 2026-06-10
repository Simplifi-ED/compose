import ContainerizationOS
import Darwin
import Foundation

// Long-running commands using `.stopProject(context)` → `ProjectShutdown.stop`:
// - `up --attach`, `exec`
// - #20 top: `.cancelOnly` + `StatsTableRenderer.finish()` terminal cleanup

/// POSIX shell convention: exit status = 128 + signal number.
package struct InterruptSignal: Sendable, Equatable {
    package let number: Int32

    package init(number: Int32) {
        self.number = number
    }

    package var exitCode: Int32 {
        number + 128
    }
}

package enum InterruptPolicy: Sendable {
    /// Cancel in-flight work only; leave project containers running (`logs -f`).
    case cancelOnly
    /// Stop scheduling new orchestration waves; accept partial state (`up` / `down`).
    case orchestration
    /// SIGTERM project containers, then force-stop (`attach up`, `exec`, `top`).
    case stopProject(ProjectShutdownContext)
}

package enum SignalForwarding {
    package enum ExitOutcome: Sendable, Equatable {
        case completed
        /// Observability commands exit 0 after a quiet cancel.
        case cancelledQuietly
        /// Orchestration interrupted; exit with `signal.exitCode` (130 for SIGINT, 143 for SIGTERM).
        case interrupted(InterruptSignal)
    }

    package static func runUntilCancelled(
        policy: InterruptPolicy,
        terminalCleanup: @Sendable () async -> Void = {},
        stopProject: @Sendable (ProjectShutdownContext) async throws -> Void = { try await ProjectShutdown.stop(context: $0) },
        body: @Sendable @escaping () async throws -> Void
    ) async throws -> ExitOutcome {
        let signalHandler = AsyncSignalHandler.create(notify: [SIGINT, SIGTERM])
        defer { signalHandler.cancel() }

        enum GroupResult: Sendable {
            case bodyFinished
            case signalled(InterruptSignal)
        }

        let race: GroupResult = try await withThrowingTaskGroup(of: GroupResult.self) { group in
            group.addTask {
                for await signal in signalHandler.signals {
                    return .signalled(InterruptSignal(number: signal))
                }
                throw CancellationError()
            }
            group.addTask {
                try await body()
                return .bodyFinished
            }

            guard let first = try await group.next() else {
                throw CancellationError()
            }

            switch first {
            case .bodyFinished:
                group.cancelAll()
                return .bodyFinished
            case .signalled(let signal):
                group.cancelAll()
                while !group.isEmpty {
                    do {
                        _ = try await group.next()
                    } catch let error where !(error is CancellationError) {
                        throw error
                    }
                }
                return .signalled(signal)
            }
        }

        switch race {
        case .bodyFinished:
            return .completed
        case .signalled(let signal):
            return try await interruptedOutcome(
                policy: policy,
                signal: signal,
                terminalCleanup: terminalCleanup,
                stopProject: stopProject
            )
        }
    }

    /// Maps a winning signal through `policy` after `terminalCleanup` (compose-verify; no POSIX signals).
    package static func interruptedOutcome(
        policy: InterruptPolicy,
        signal: InterruptSignal,
        terminalCleanup: @Sendable () async -> Void = {},
        stopProject: @Sendable (ProjectShutdownContext) async throws -> Void = { try await ProjectShutdown.stop(context: $0) }
    ) async throws -> ExitOutcome {
        await terminalCleanup()
        switch policy {
        case .cancelOnly:
            return .cancelledQuietly
        case .orchestration:
            return .interrupted(signal)
        case .stopProject(let context):
            do {
                try await stopProject(context)
            } catch {
                fputs(
                    """
                    Warning: couldn't stop all project containers after interrupt: \
                    \(error.localizedDescription).\n
                    """,
                    stderr
                )
            }
            return .interrupted(signal)
        }
    }
}
