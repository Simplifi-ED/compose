import ContainerizationOS
import Darwin
import Foundation

// Future long-running commands:
// - #21 attach up / #19 exec: `.stopProject(context)` → `ProjectShutdown.stop`
// - #20 top streaming: `.cancelOnly` + alternate-screen `terminalCleanup`

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
                try await drainCancelledBodyErrors(group: &group)
                return .signalled(signal)
            }
        }

        switch race {
        case .bodyFinished:
            return .completed
        case .signalled(let signal):
            switch policy {
            case .cancelOnly:
                await terminalCleanup()
                return .cancelledQuietly
            case .orchestration:
                await terminalCleanup()
                return .interrupted(signal)
            case .stopProject(let context):
                await terminalCleanup()
                try await ProjectShutdown.stop(context: context)
                return .interrupted(signal)
            }
        }
    }

    /// After a signal wins the race, prefer a real compose failure from the body over interrupt.
    private static func drainCancelledBodyErrors<GroupResult: Sendable>(
        group: inout ThrowingTaskGroup<GroupResult, Error>
    ) async throws {
        while !group.isEmpty {
            do {
                _ = try await group.next()
            } catch let error where !(error is CancellationError) {
                throw error
            }
        }
    }
}
