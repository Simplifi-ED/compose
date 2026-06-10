import ContainerCommands
import Foundation

public enum ServiceRunner {
    public static func up(plans: [ServicePlan]) async throws {
        try await up(layers: [plans])
    }

    public static func up(layers: [[ServicePlan]], progress: WaveProgressHandlers? = nil) async throws {
        var startedWaves: [[String]] = []
        do {
            for (index, layer) in layers.enumerated() {
                try Task.checkCancellation()
                await progress?.onWaveStart?(index + 1, layers.count, layer.map(\.serviceName))
                let result = await parallelRun(
                    layer.map { (label: $0.serviceName, collectOnSuccess: $0.name, value: $0) },
                    onCompletion: progress?.onServiceComplete
                ) { plan in
                    try await ContainerTeardown.runDetachedContainerRespectingCancellation(
                        containerName: plan.name
                    ) {
                        let command = try Application.ContainerRun.parse(plan.runArguments)
                        try await command.run()
                    }
                }
                if result.wasInterrupted {
                    throw CancellationError()
                }
                if !result.succeeded.isEmpty {
                    startedWaves.append(result.succeeded)
                }
                if !result.failures.isEmpty {
                    throw ComposeError.multipleServiceFailures(result.failures)
                }
                await progress?.onWaveComplete?(index + 1)
            }
        } catch {
            if error is CancellationError {
                throw error
            }
            // Roll back in reverse startup order; parallel within each wave.
            let rollbackFailures = await rollbackStartedContainers(startedWaves.reversed(), teardown: { name in
                try await ContainerTeardown.teardown(id: name)
            })
            if !rollbackFailures.isEmpty {
                let started = startedWaves.flatMap { $0 }
                let rollbackMessage = ComposeError.rollbackFailed(
                    started: started,
                    failures: rollbackFailures
                ).localizedDescription
                fputs("Warning: \(rollbackMessage)\n", stderr)
            }
            throw error
        }
    }

    public static func down(
        containers: [DiscoveredContainer],
        onRemoved: (@Sendable (String) -> Void)? = nil,
        progress: WaveProgressHandlers? = nil
    ) async throws {
        try await down(layers: [containers], onRemoved: onRemoved, progress: progress)
    }

    public static func down(
        layers: [[DiscoveredContainer]],
        onRemoved: (@Sendable (String) -> Void)? = nil,
        progress: WaveProgressHandlers? = nil
    ) async throws {
        _ = try await runContainerWaves(
            layers: layers,
            progress: progress,
            failFast: true
        ) { container in
            try await ContainerTeardown.teardownRespectingCancellation(id: container.name)
        } onWaveComplete: { layer in
            if let onRemoved {
                for container in layer {
                    onRemoved(container.name)
                }
            }
        }
    }

    /// SIGTERM each container with grace, then SIGKILL. Collects per-container failures.
    package static func stopGracefully(
        layers: [[DiscoveredContainer]],
        options: GracefulStopOptions
    ) async throws -> [(name: String, error: Error)] {
        try await runContainerWaves(
            layers: layers,
            progress: nil,
            failFast: false
        ) { container in
            try await ContainerTeardown.stopGracefully(id: container.name, options: options)
        } onWaveComplete: { _ in }
    }

    public static func rollbackStartedContainers(
        _ waves: [[String]],
        teardown: @escaping @Sendable (String) async throws -> Void = { name in
            try await ContainerTeardown.teardown(id: name)
        }
    ) async -> [(container: String, error: Error)] {
        var failures: [(container: String, error: Error)] = []
        for wave in waves {
            if Task.isCancelled {
                break
            }
            guard !wave.isEmpty else { continue }
            let result = await parallelRun(
                wave.map { (label: $0, collectOnSuccess: nil, value: $0) }
            ) { name in
                try await ContainerTeardown.teardownRespectingCancellation(id: name) {
                    try await teardown(name)
                }
            }
            if result.wasInterrupted {
                break
            }
            failures.append(contentsOf: result.failures.map { (container: $0.service, error: $0.error) })
        }
        return failures
    }

    private struct ParallelRunResult: Sendable {
        let succeeded: [String]
        let failures: [(service: String, error: Error)]
        let wasInterrupted: Bool
    }

    private static func runContainerWaves(
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

    private static func parallelRun<T: Sendable>(
        _ items: [(label: String, collectOnSuccess: String?, value: T)],
        onCompletion: (@Sendable (String, Bool) async -> Void)? = nil,
        work: @escaping @Sendable (T) async throws -> Void
    ) async -> ParallelRunResult {
        guard !items.isEmpty else {
            return ParallelRunResult(succeeded: [], failures: [], wasInterrupted: false)
        }

        if Task.isCancelled {
            return ParallelRunResult(succeeded: [], failures: [], wasInterrupted: true)
        }

        var succeeded: [String] = []
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
                    if let collected = result.1 {
                        succeeded.append(collected)
                    }
                    await onCompletion?(result.0, true)
                }
            }
        }

        return ParallelRunResult(
            succeeded: succeeded,
            failures: failures,
            wasInterrupted: wasInterrupted || Task.isCancelled
        )
    }
}
