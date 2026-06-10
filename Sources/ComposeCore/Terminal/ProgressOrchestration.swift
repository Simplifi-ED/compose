import ArgumentParser
import Foundation

/// Compose service label shown in progress output; falls back to the container name.
package func progressServiceLabel(containerName: String, serviceName: String?) -> String {
    serviceName ?? containerName
}

/// Builds a `ProgressLines` actor and matching `WaveProgressHandlers` for `up`/`down`.
package func makeProgressOrchestration(
    display: ProgressDisplay,
    phase: ProgressPhase,
    label: @escaping @Sendable (String) -> String = { $0 },
    write: @escaping @Sendable (String) -> Void = { fputs($0, stderr) }
) -> (lines: ProgressLines, handlers: WaveProgressHandlers) {
    let lines = ProgressLines(display: display, phase: phase, write: write)
    let handlers = WaveProgressHandlers(
        onWaveStart: { wave, total, services in
            await lines.beginWave(wave: wave, total: total, services: services.map(label))
        },
        onServiceComplete: { service, succeeded in
            await lines.markComplete(service: label(service), succeeded: succeeded)
        },
        onWaveComplete: { _ in
            await lines.finishWave()
        }
    )
    return (lines, handlers)
}

/// Runs orchestration work with progress cleanup on success or failure.
package func runWithProgress(
    lines: ProgressLines,
    skipFinishOnCancellation: Bool = false,
    _ body: () async throws -> Void
) async throws {
    do {
        try await body()
    } catch {
        if !(skipFinishOnCancellation && error is CancellationError) {
            await lines.finish()
        }
        throw error
    }
    await lines.finish()
}

/// Wraps `up`/`down` work with signal handling, progress cleanup, and exit 130 on interrupt.
package func runOrchestrationCommand(
    lines: ProgressLines,
    interruptedMessage: String,
    body: @Sendable @escaping () async throws -> Void
) async throws {
    let outcome = try await SignalForwarding.runUntilCancelled(
        policy: .orchestration,
        terminalCleanup: { await lines.finish() },
        body: {
            try await runWithProgress(lines: lines, skipFinishOnCancellation: true) {
                try await body()
            }
        }
    )
    if case .interrupted(let signal) = outcome {
        fputs("\(interruptedMessage)\n", stderr)
        throw ExitCode(signal.exitCode)
    }
}
