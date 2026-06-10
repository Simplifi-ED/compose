import Darwin
import Foundation

/// Shared foreground log-follow orchestration for `logs -f` and `up --attach`.
package enum LogFollowSession {
    private enum ParallelResult: Sendable {
        case multiplexFinished
        case parallelFinished
    }

    package static func prepareStdout() {
        fflush(stdout)
        setbuf(stdout, nil)
    }

    package static func runUntilCancelled(
        sources: [ServiceLogSource],
        options: LogStreamOptions,
        policy: InterruptPolicy,
        stopProject: @Sendable (ProjectShutdownContext) async throws -> Void = {
            try await ProjectShutdown.stop(context: $0)
        },
        multiplex: @escaping @Sendable ([ServiceLogSource], LogStreamOptions) async throws -> Void = defaultMultiplex,
        parallelUntilComplete: (@Sendable () async throws -> Void)? = nil,
        onMultiplexError: (@Sendable (Error) -> Void)? = nil,
        onQuietCancel: (@Sendable () -> Void)? = nil
    ) async throws -> SignalForwarding.ExitOutcome {
        prepareStdout()

        let outcome = try await SignalForwarding.runUntilCancelled(
            policy: policy,
            stopProject: stopProject
        ) {
            if let parallelUntilComplete {
                try await runMultiplexUntilParallelCompletes(
                    sources: sources,
                    options: options,
                    multiplex: multiplex,
                    onMultiplexError: onMultiplexError,
                    parallelUntilComplete: parallelUntilComplete
                )
            } else {
                try await runMultiplex(
                    sources: sources,
                    options: options,
                    multiplex: multiplex,
                    onMultiplexError: onMultiplexError
                )
            }
        }

        if outcome == .cancelledQuietly {
            onQuietCancel?()
        }
        return outcome
    }

    package static func runMultiplexUntilParallelCompletes(
        sources: [ServiceLogSource],
        options: LogStreamOptions,
        multiplex: @escaping @Sendable ([ServiceLogSource], LogStreamOptions) async throws -> Void = defaultMultiplex,
        onMultiplexError: (@Sendable (Error) -> Void)? = nil,
        parallelUntilComplete: @escaping @Sendable () async throws -> Void
    ) async throws {
        try await withThrowingTaskGroup(of: ParallelResult.self) { group in
            group.addTask {
                do {
                    try await multiplex(sources, options)
                } catch {
                    onMultiplexError?(error)
                }
                return .multiplexFinished
            }
            group.addTask {
                try await parallelUntilComplete()
                return .parallelFinished
            }

            while let result = try await group.next() {
                if result == .parallelFinished {
                    group.cancelAll()
                    while !group.isEmpty {
                        do {
                            _ = try await group.next()
                        } catch is CancellationError {
                            continue
                        }
                    }
                    return
                }
            }
        }
    }

    private static func defaultMultiplex(
        sources: [ServiceLogSource],
        options: LogStreamOptions
    ) async throws {
        try await LogMultiplexer.run(sources: sources, options: options)
    }

    private static func runMultiplex(
        sources: [ServiceLogSource],
        options: LogStreamOptions,
        multiplex: @escaping @Sendable ([ServiceLogSource], LogStreamOptions) async throws -> Void,
        onMultiplexError: (@Sendable (Error) -> Void)?
    ) async throws {
        do {
            try await multiplex(sources, options)
        } catch {
            onMultiplexError?(error)
            throw error
        }
    }
}
