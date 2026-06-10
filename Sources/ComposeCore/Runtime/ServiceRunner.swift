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
                await progress?.onWaveStart?(index + 1, layers.count, layer.map(\.serviceName))
                let result = await parallelRunCollecting(
                    layer.map { (label: $0.serviceName, successValue: $0.name, value: $0) },
                    onCompletion: progress?.onServiceComplete
                ) { plan in
                    let command = try Application.ContainerRun.parse(plan.runArguments)
                    try await command.run()
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
        for (index, layer) in layers.enumerated() {
            await progress?.onWaveStart?(index + 1, layers.count, layer.map(\.name))
            let result = await parallelRun(
                layer.map { (label: $0.name, value: $0) },
                onCompletion: progress?.onServiceComplete
            ) { container in
                try await ContainerTeardown.teardown(id: container.name)
            }
            if !result.failures.isEmpty {
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
            // Clear progress (spinner) before container names go to stdout.
            await progress?.onWaveComplete?(index + 1)
            if let onRemoved {
                for container in layer {
                    onRemoved(container.name)
                }
            }
        }
    }

    public static func rollbackStartedContainers(
        _ waves: [[String]],
        teardown: @escaping @Sendable (String) async throws -> Void = { name in
            try await ContainerTeardown.teardown(id: name)
        }
    ) async -> [(container: String, error: Error)] {
        var failures: [(container: String, error: Error)] = []
        for wave in waves {
            guard !wave.isEmpty else { continue }
            let result = await parallelRun(
                wave.map { (label: $0, value: $0) }
            ) { name in
                try await teardown(name)
            }
            failures.append(contentsOf: result.failures.map { (container: $0.service, error: $0.error) })
        }
        return failures
    }

    private struct ParallelRunResult: Sendable {
        let succeeded: [String]
        let failures: [(service: String, error: Error)]
    }

    private static func parallelRun<T: Sendable>(
        _ items: [(label: String, value: T)],
        onCompletion: (@Sendable (String, Bool) async -> Void)? = nil,
        work: @escaping @Sendable (T) async throws -> Void
    ) async -> ParallelRunResult {
        guard !items.isEmpty else {
            return ParallelRunResult(succeeded: [], failures: [])
        }

        var failures: [(service: String, error: Error)] = []

        await withTaskGroup(of: (String, Error?).self) { group in
            for item in items {
                group.addTask {
                    do {
                        try await work(item.value)
                        return (item.label, nil)
                    } catch {
                        return (item.label, error)
                    }
                }
            }

            for await result in group {
                if let error = result.1 {
                    failures.append((service: result.0, error: error))
                }
                await onCompletion?(result.0, result.1 == nil)
            }
        }

        return ParallelRunResult(succeeded: [], failures: failures)
    }

    private static func parallelRunCollecting<T: Sendable>(
        _ items: [(label: String, successValue: String, value: T)],
        onCompletion: (@Sendable (String, Bool) async -> Void)? = nil,
        work: @escaping @Sendable (T) async throws -> Void
    ) async -> ParallelRunResult {
        guard !items.isEmpty else {
            return ParallelRunResult(succeeded: [], failures: [])
        }

        var succeeded: [String] = []
        var failures: [(service: String, error: Error)] = []

        await withTaskGroup(of: (String, String, Error?).self) { group in
            for item in items {
                group.addTask {
                    do {
                        try await work(item.value)
                        return (item.label, item.successValue, nil)
                    } catch {
                        return (item.label, item.successValue, error)
                    }
                }
            }

            for await result in group {
                if let error = result.2 {
                    failures.append((service: result.0, error: error))
                } else {
                    succeeded.append(result.1)
                }
                await onCompletion?(result.0, result.2 == nil)
            }
        }

        return ParallelRunResult(succeeded: succeeded, failures: failures)
    }
}
