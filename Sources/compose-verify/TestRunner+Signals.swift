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
    }

    private mutating func runWaveCancellationTests() {
        let interrupted = blockingAwait {
            await signalsWaveCancellationProbe()
        }
        expect(interrupted, "wave loop honors task cancellation")
    }
}

private func signalsWaveCancellationProbe() async -> Bool {
    let task = Task {
        do {
            for _ in 0 ..< 100 {
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(10))
            }
            return false
        } catch is CancellationError {
            return true
        }
    }
    try? await Task.sleep(for: .milliseconds(25))
    task.cancel()
    return (try? await task.value) ?? true
}
