import Foundation

extension ServiceRunner {
    package struct ParallelRunResult: Sendable {
        let succeeded: [String]
        let completed: [String]
        let failures: [(service: String, error: Error)]
        let wasInterrupted: Bool
    }

    package static func runContainerWaves(
        layers: [[DiscoveredContainer]],
        progress: WaveProgressHandlers?,
        failFast: Bool,
        work: @escaping @Sendable (DiscoveredContainer) async throws -> Void,
        onWaveComplete: @escaping @Sendable ([DiscoveredContainer]) async -> Void
    ) async throws -> [(name: String, error: Error)] {
        var collectedFailures: [(name: String, error: Error)] = []

        for (index, layer) in layers.enumerated() {
            try Task.checkCancellation()
            await progress?.onWaveStart?(index + 1, layers.count, layer.map(\.name))
            let result = await parallelRun(
                layer.map { (label: $0.name, collectOnSuccess: nil, value: $0) },
                onCompletion: progress?.onServiceComplete
            ) { container in
                try await work(container)
            }
            if result.wasInterrupted {
                let removed = layer.filter { result.completed.contains($0.name) }
                if !removed.isEmpty {
                    await onWaveComplete(removed)
                }
                throw CancellationError()
            }
            if !result.failures.isEmpty {
                if failFast {
                    let remaining = layers.count - index - 1
                    if remaining > 0 {
                        fputs(
                            """
                            Warning: compose down failed in wave \(index + 1) of \(layers.count); \
                            \(remaining) later wave(s) were not run.\n
                            """,
                            stderr
                        )
                    }
                    throw ComposeError.multipleServiceFailures(result.failures)
                }
                collectedFailures.append(contentsOf: result.failures.map { (name: $0.service, error: $0.error) })
            }
            await progress?.onWaveComplete?(index + 1)
            await onWaveComplete(layer)
        }

        return collectedFailures
    }

    package static func parallelRun<T: Sendable>(
        _ items: [(label: String, collectOnSuccess: String?, value: T)],
        onCompletion: (@Sendable (String, Bool) async -> Void)? = nil,
        work: @escaping @Sendable (T) async throws -> Void
    ) async -> ParallelRunResult {
        guard !items.isEmpty else {
            return ParallelRunResult(succeeded: [], completed: [], failures: [], wasInterrupted: false)
        }

        if Task.isCancelled {
            return ParallelRunResult(succeeded: [], completed: [], failures: [], wasInterrupted: true)
        }

        var succeeded: [String] = []
        var completed: [String] = []
        var failures: [(service: String, error: Error)] = []
        var wasInterrupted = false

        await withTaskGroup(of: (String, String?, Error?).self) { group in
            for item in items {
                if Task.isCancelled {
                    wasInterrupted = true
                    group.cancelAll()
                    break
                }
                group.addTask {
                    do {
                        try Task.checkCancellation()
                        try await work(item.value)
                        return (item.label, item.collectOnSuccess, nil)
                    } catch is CancellationError {
                        return (item.label, item.collectOnSuccess, CancellationError())
                    } catch {
                        return (item.label, item.collectOnSuccess, error)
                    }
                }
            }

            for await result in group {
                if let error = result.2 {
                    if error is CancellationError {
                        wasInterrupted = true
                    } else {
                        failures.append((service: result.0, error: error))
                        await onCompletion?(result.0, false)
                    }
                } else {
                    completed.append(result.0)
                    if let collected = result.1 {
                        succeeded.append(collected)
                    }
                    await onCompletion?(result.0, true)
                }
            }
        }

        return ParallelRunResult(
            succeeded: succeeded,
            completed: completed,
            failures: failures,
            wasInterrupted: wasInterrupted || Task.isCancelled
        )
    }
}
