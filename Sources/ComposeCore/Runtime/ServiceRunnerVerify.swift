import Foundation

extension ServiceRunner {
    /// Verifies `parallelRun` never exceeds `maxConcurrent` in-flight work (compose-verify).
    package static func parallelRunPeakConcurrency(
        maxConcurrent: Int?,
        itemCount: Int
    ) async -> Int {
        actor ConcurrencyTracker {
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

        let tracker = ConcurrencyTracker()
        let items = (0..<itemCount).map { index in
            ParallelRunItem(label: "item-\(index)", collectOnSuccess: nil, value: index)
        }
        _ = await parallelRun(items, maxConcurrent: maxConcurrent) { _ in
            await tracker.enter()
            try await Task.sleep(for: .milliseconds(50))
            await tracker.leave()
        }
        return await tracker.peak
    }

    /// Verifies throttled `parallelRun` still records completed work after cancellation (compose-verify).
    package static func parallelRunDrainsCompletedWorkOnCancellation() async -> [String] {
        let items = [
            ParallelRunItem(label: "fast", collectOnSuccess: "fast", value: "fast"),
            ParallelRunItem(label: "slow", collectOnSuccess: "slow", value: "slow")
        ]
        let task = Task {
            await parallelRun(items, maxConcurrent: 1) { label in
                if label == "slow" {
                    try await Task.sleep(for: .seconds(30))
                }
            }
        }
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()
        let result = await task.value
        return result.completed
    }

    /// Verifies `parallelRun` marks interruption when its parent task is cancelled (compose-verify).
    package static func parallelRunHonorsCancellation() async -> Bool {
        let task = Task {
            let result = await parallelRun(
                [ParallelRunItem(label: "work", collectOnSuccess: nil, value: ())],
                work: { _ in
                    try await Task.sleep(for: .seconds(30))
                }
            )
            return result.wasInterrupted
        }
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()
        return await task.value == true
    }

    /// Verifies `up` does not roll back prior waves when cancelled mid-orchestration (compose-verify).
    package static func upSkipsRollbackOnCancellation() async -> (started: [String], rollback: [String]) {
        actor Recorder {
            private(set) var started: [String] = []
            private(set) var rollback: [String] = []

            func recordStarted(_ name: String) {
                started.append(name)
            }

            func recordRollback(_ name: String) {
                rollback.append(name)
            }
        }

        let recorder = Recorder()
        let fast = ServicePlan(serviceName: "fast", name: "demo_fast", runArguments: [])
        let slow = ServicePlan(serviceName: "slow", name: "demo_slow", runArguments: [])

        let task = Task {
            try await orchestrateUp(
                layers: [[fast], [slow]],
                progress: nil,
                healthContext: nil,
                hooks: UpOperationHooks(
                    runContainer: { plan in
                        if plan.serviceName == "slow" {
                            try await Task.sleep(for: .seconds(30))
                        }
                        await recorder.recordStarted(plan.name)
                    },
                    rollbackTeardown: { name in
                        await recorder.recordRollback(name)
                    },
                    waitForDependencies: { _, _ in }
                )
            )
        }

        while await recorder.started.isEmpty {
            try? await Task.sleep(for: .milliseconds(5))
        }
        try? await Task.sleep(for: .milliseconds(25))
        task.cancel()
        _ = try? await task.value

        return (await recorder.started, await recorder.rollback)
    }

    /// Verifies `down` reports removals for containers torn down before interrupt (compose-verify).
    package static func downReportsPartialRemovalOnInterrupt() async -> [String] {
        final class Recorder: @unchecked Sendable {
            private let lock = NSLock()
            private var names: [String] = []

            func add(_ name: String) {
                lock.lock()
                defer { lock.unlock() }
                names.append(name)
            }

            var snapshot: [String] {
                lock.lock()
                defer { lock.unlock() }
                return names
            }
        }

        let recorder = Recorder()
        let fast = DiscoveredContainer(name: "demo_fast", serviceName: "fast")
        let slow = DiscoveredContainer(name: "demo_slow", serviceName: "slow")

        let task = Task {
            try await orchestrateDown(
                layers: [[fast, slow]],
                onRemoved: { name in
                    recorder.add(name)
                },
                progress: nil,
                teardown: { container in
                    if container.name == "demo_slow" {
                        try await Task.sleep(for: .seconds(30))
                    }
                }
            )
        }

        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()
        _ = await task.result

        return recorder.snapshot
    }
}
