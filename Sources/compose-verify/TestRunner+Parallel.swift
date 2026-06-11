import ArgumentParser
import ComposeCore
import Foundation

extension TestRunner {
    mutating func runParallelTests() {
        runParallelOptionsValidationTests()
        runParallelRunConcurrencyTests()
        runParallelRunCancellationTests()
        runRollbackThrottleTests()
    }

    private mutating func runParallelOptionsValidationTests() {
        expectThrows(ValidationError.self, "non-positive --parallel rejected") {
            try ParallelOptions.validateParallel(0)
        }
        expectThrows(ValidationError.self, "negative --parallel rejected") {
            try ParallelOptions.validateParallel(-1)
        }
        do {
            try ParallelOptions.validateParallel(nil)
            expect(true, "omitted --parallel validates")
        } catch {
            expect(false, "omitted --parallel validates")
        }
        do {
            try ParallelOptions.validateParallel(2)
            expect(true, "positive --parallel validates")
        } catch {
            expect(false, "positive --parallel validates")
        }
    }

    private mutating func runParallelRunConcurrencyTests() {
        let peakUnlimited = blockingAwait {
            await ServiceRunner.parallelRunPeakConcurrency(maxConcurrent: nil, itemCount: 6)
        }
        expect(peakUnlimited == 6, "default parallelRun runs all items in a wave at once")

        let peakAtTwo = blockingAwait {
            await ServiceRunner.parallelRunPeakConcurrency(maxConcurrent: 2, itemCount: 6)
        }
        expect(peakAtTwo <= 2, "parallelRun peak concurrency respects --parallel 2")

        let peakAtOne = blockingAwait {
            await ServiceRunner.parallelRunPeakConcurrency(maxConcurrent: 1, itemCount: 4)
        }
        expect(peakAtOne == 1, "parallelRun with --parallel 1 runs one-at-a-time")
    }

    private mutating func runParallelRunCancellationTests() {
        let completed = blockingAwait {
            await ServiceRunner.parallelRunDrainsCompletedWorkOnCancellation()
        }
        expect(completed.contains("fast"), "throttled parallelRun drains completed work on cancellation")
    }

    private mutating func runRollbackThrottleTests() {
        let peak = blockingAwait { () -> Int in
            actor TearDownTracker {
                private(set) var peak = 0
                private var inFlight = 0

                func enter() {
                    inFlight += 1
                    peak = max(peak, inFlight)
                }

                func leave() {
                    inFlight -= 1
                }
            }

            let tracker = TearDownTracker()
            _ = await ServiceRunner.rollbackStartedContainers(
                [["a", "b", "c", "d"]],
                execution: WaveExecutionPolicy(maxConcurrent: 1)
            ) { _ in
                await tracker.enter()
                try await Task.sleep(for: .milliseconds(20))
                await tracker.leave()
            }
            return await tracker.peak
        }
        expect(peak == 1, "rollback honors --parallel throttle")
    }
}
