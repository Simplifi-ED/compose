import Foundation

extension ServiceRunner {
    package struct ParallelRunResult: Sendable {
        let succeeded: [String]
        let completed: [String]
        let failures: [(service: String, error: Error)]
        let wasInterrupted: Bool
    }

    package struct ParallelRunItem<T: Sendable>: Sendable {
        let label: String
        let collectOnSuccess: String?
        let value: T
    }

    private struct ParallelTaskResult: Sendable {
        let label: String
        let collectOnSuccess: String?
        let error: Error?
    }

    private struct ParallelRunAccumulator {
        var succeeded: [String] = []
        var completed: [String] = []
        var failures: [(service: String, error: Error)] = []
        var wasInterrupted = false

        mutating func record(
            _ result: ParallelTaskResult,
            onCompletion: (@Sendable (String, Bool) async -> Void)?
        ) async {
            if let error = result.error {
                if error is CancellationError {
                    wasInterrupted = true
                } else {
                    failures.append((service: result.label, error: error))
                    await onCompletion?(result.label, false)
                }
            } else {
                completed.append(result.label)
                if let collected = result.collectOnSuccess {
                    succeeded.append(collected)
                }
                await onCompletion?(result.label, true)
            }
        }
    }

    private static func runParallelItem<T: Sendable>(
        _ item: ParallelRunItem<T>,
        work: @escaping @Sendable (T) async throws -> Void
    ) async -> ParallelTaskResult {
        do {
            try Task.checkCancellation()
            try await work(item.value)
            return ParallelTaskResult(
                label: item.label,
                collectOnSuccess: item.collectOnSuccess,
                error: nil
            )
        } catch is CancellationError {
            return ParallelTaskResult(
                label: item.label,
                collectOnSuccess: item.collectOnSuccess,
                error: CancellationError()
            )
        } catch {
            return ParallelTaskResult(
                label: item.label,
                collectOnSuccess: item.collectOnSuccess,
                error: error
            )
        }
    }

    package static func parallelRun<T: Sendable>(
        _ items: [ParallelRunItem<T>],
        maxConcurrent: Int? = nil,
        onCompletion: (@Sendable (String, Bool) async -> Void)? = nil,
        work: @escaping @Sendable (T) async throws -> Void
    ) async -> ParallelRunResult {
        guard !items.isEmpty else {
            return ParallelRunResult(succeeded: [], completed: [], failures: [], wasInterrupted: false)
        }

        if Task.isCancelled {
            return ParallelRunResult(succeeded: [], completed: [], failures: [], wasInterrupted: true)
        }

        var accumulator = ParallelRunAccumulator()
        let limit: Int = if let maxConcurrent, maxConcurrent > 0 {
            maxConcurrent
        } else {
            items.count
        }

        await withTaskGroup(of: ParallelTaskResult.self) { group in
            var nextIndex = 0
            var stopEnqueueing = false

            func addWork(for item: ParallelRunItem<T>) {
                group.addTask {
                    await runParallelItem(item, work: work)
                }
            }

            let seedCount = min(limit, items.count)
            for _ in 0..<seedCount {
                if Task.isCancelled {
                    accumulator.wasInterrupted = true
                    stopEnqueueing = true
                    group.cancelAll()
                    break
                }
                addWork(for: items[nextIndex])
                nextIndex += 1
            }

            for await result in group {
                await accumulator.record(result, onCompletion: onCompletion)
                if Task.isCancelled {
                    accumulator.wasInterrupted = true
                    stopEnqueueing = true
                    group.cancelAll()
                }
                if !stopEnqueueing, nextIndex < items.count {
                    addWork(for: items[nextIndex])
                    nextIndex += 1
                }
            }
        }

        return ParallelRunResult(
            succeeded: accumulator.succeeded,
            completed: accumulator.completed,
            failures: accumulator.failures,
            wasInterrupted: accumulator.wasInterrupted || Task.isCancelled
        )
    }
}
