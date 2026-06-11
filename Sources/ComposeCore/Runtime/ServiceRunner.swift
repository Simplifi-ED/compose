import ContainerCommands
import Foundation

public enum ServiceRunner {
    /// Verifies `parallelRun` marks interruption when its parent task is cancelled (compose-verify).
    package static func parallelRunHonorsCancellation() async -> Bool {
        let task = Task {
            let result = await parallelRun(
                [(label: "work", collectOnSuccess: nil, value: ())],
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

    public static func up(plans: [ServicePlan]) async throws {
        try await up(layers: [plans])
    }

    public static func up(layers: [[ServicePlan]], progress: WaveProgressHandlers? = nil) async throws {
        try await up(
            layers: layers,
            progress: progress,
            runContainer: { plan in
                try await ContainerTeardown.teardownRespectingCancellation(id: plan.name) {
                    let command = try Application.ContainerRun.parse(plan.runArguments)
                    try await command.run()
                }
            },
            rollbackTeardown: { name in
                try await ContainerTeardown.teardown(id: name)
            }
        )
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
            try await up(
                layers: [[fast], [slow]],
                progress: nil,
                runContainer: { plan in
                    if plan.serviceName == "slow" {
                        try await Task.sleep(for: .seconds(30))
                    }
                    await recorder.recordStarted(plan.name)
                },
                rollbackTeardown: { name in
                    await recorder.recordRollback(name)
                }
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

    private static func up(
        layers: [[ServicePlan]],
        progress: WaveProgressHandlers?,
        runContainer: @escaping @Sendable (ServicePlan) async throws -> Void,
        rollbackTeardown: @escaping @Sendable (String) async throws -> Void
    ) async throws {
        var startedWaves: [[String]] = []
        do {
            for (index, layer) in layers.enumerated() {
                try Task.checkCancellation()
                // Progress keys on container names so replicas of one service stay distinct.
                await progress?.onWaveStart?(index + 1, layers.count, layer.map(\.name))
                let result = await parallelRun(
                    layer.map { (label: $0.name, collectOnSuccess: $0.name, value: $0) },
                    onCompletion: progress?.onServiceComplete
                ) { plan in
                    try await runContainer(plan)
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
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Roll back in reverse startup order; parallel within each wave.
            let rollbackFailures = await rollbackStartedContainers(startedWaves.reversed(), teardown: rollbackTeardown)
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
        try await down(
            layers: layers,
            onRemoved: onRemoved,
            progress: progress,
            teardown: { container in
                try await ContainerTeardown.teardownRespectingCancellation(id: container.name)
            }
        )
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
            try await down(
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

    private static func down(
        layers: [[DiscoveredContainer]],
        onRemoved: (@Sendable (String) -> Void)?,
        progress: WaveProgressHandlers?,
        teardown: @escaping @Sendable (DiscoveredContainer) async throws -> Void
    ) async throws {
        _ = try await runContainerWaves(
            layers: layers,
            progress: progress,
            failFast: true
        ) { container in
            try await teardown(container)
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
        let completed: [String]
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

    private static func parallelRun<T: Sendable>(
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
