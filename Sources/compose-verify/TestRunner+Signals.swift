import ArgumentParser
import ComposeCore
import ContainerResource
import Darwin
import Foundation

extension TestRunner {
    mutating func runSignalsTests() {
        runGracefulStopOptionsTests()
        runShutdownTimeoutValidationTests()
        runInterruptExitCodeTests()
        runWaveCancellationTests()
        runSignalForwardingPolicyTests()
    }

    private mutating func runGracefulStopOptionsTests() {
        let defaults = GracefulStopOptions()
        expect(defaults.graceSeconds == 10, "default grace period is 10 seconds")

        let custom = GracefulStopOptions(graceSeconds: 30)
        let mapped = ContainerTeardown.stopOptions(for: custom)
        expect(mapped.timeoutInSeconds == 30, "stop options map grace seconds")
        expect(mapped.signal == "SIGTERM", "stop options use SIGTERM")
    }

    private mutating func runShutdownTimeoutValidationTests() {
        expect(GracefulStopOptions(graceSeconds: 5).graceSeconds == 5, "grace seconds constructor")

        expectThrows(ValidationError.self, "non-positive timeout rejected") {
            try ShutdownTimeoutOptions.validateTimeout(0)
        }
    }

    private mutating func runInterruptExitCodeTests() {
        expect(InterruptSignal(number: SIGINT).exitCode == 130, "SIGINT maps to exit 130")
        expect(InterruptSignal(number: SIGTERM).exitCode == 143, "SIGTERM maps to exit 143")
        expect(
            orchestrationInterruptedExitCode(for: InterruptSignal(number: SIGINT)) == 130,
            "orchestration interrupt maps to exit 130"
        )
        expect(
            orchestrationInterruptedExitCode(for: InterruptSignal(number: SIGTERM)) == 143,
            "orchestration interrupt maps to exit 143"
        )
    }

    private mutating func runWaveCancellationTests() {
        let interrupted = blockingAwait {
            await ServiceRunner.parallelRunHonorsCancellation()
        }
        expect(interrupted, "parallelRun honors parent task cancellation")
    }

    private mutating func runSignalForwardingPolicyTests() {
        let signal = InterruptSignal(number: SIGINT)

        let cancelOnly = blockingAwait {
            try? await SignalForwarding.interruptedOutcome(policy: .cancelOnly, signal: signal)
        }
        expect(cancelOnly == .cancelledQuietly, "cancelOnly maps to cancelledQuietly")

        let orchestration = blockingAwait {
            try? await SignalForwarding.interruptedOutcome(policy: .orchestration, signal: signal)
        }
        expect(orchestration == .interrupted(signal), "orchestration maps to interrupted(signal)")

        let stopProject = blockingAwait {
            try? await SignalForwarding.interruptedOutcome(
                policy: .stopProject(
                    ProjectShutdownContext(
                        projectName: "demo",
                        composeFile: nil,
                        fileURLs: nil,
                        options: GracefulStopOptions()
                    )
                ),
                signal: signal,
                stopProject: { _ in }
            )
        }
        expect(stopProject == .interrupted(signal), "stopProject maps to interrupted(signal)")

        let cleanupCount = blockingAwait { () -> Int in
            final class Counter: @unchecked Sendable {
                var value = 0
            }
            let counter = Counter()
            _ = try? await SignalForwarding.interruptedOutcome(
                policy: .cancelOnly,
                signal: signal,
                terminalCleanup: { counter.value += 1 }
            )
            return counter.value
        }
        expect(cleanupCount == 1, "interruptedOutcome runs terminalCleanup once")

        let completed = blockingAwait {
            try? await SignalForwarding.runUntilCancelled(policy: .cancelOnly) { }
        }
        expect(completed == .completed, "runUntilCancelled returns completed when body finishes")
    }
}
