import ContainerCommands
import Foundation

public enum ServiceRunner {
    public static func up(plans: [ServicePlan]) async throws {
        try await up(layers: [plans])
    }

    public static func up(layers: [[ServicePlan]]) async throws {
        var startedWaves: [[String]] = []
        do {
            for layer in layers {
                let result = await parallelRun(
                    layer.map { ParallelWorkItem(label: $0.serviceName, successValue: $0.name, value: $0) }
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

    public static func down(containers: [DiscoveredContainer]) async throws {
        try await down(layers: [containers])
    }

    public static func down(layers: [[DiscoveredContainer]]) async throws {
        for (index, layer) in layers.enumerated() {
            let result = await parallelRun(
                layer.map { ParallelWorkItem(label: $0.name, successValue: nil, value: $0) }
            ) { container in
                try await ContainerTeardown.teardown(id: container.name)
            }
            if !result.failures.isEmpty {
                let completed = index
                let remaining = layers.count - completed - 1
                if remaining > 0 {
                    let wave = completed + 1
                    fputs(
                        """
                        Warning: compose down failed in wave \(wave) of \(layers.count); \
                        \(remaining) later wave(s) were not run.\n
                        """,
                        stderr
                    )
                }
                throw ComposeError.multipleServiceFailures(result.failures)
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
                wave.map { ParallelWorkItem(label: $0, successValue: nil, value: $0) }
            ) { name in
                try await teardown(name)
            }
            failures.append(contentsOf: result.failures.map { (container: $0.service, error: $0.error) })
        }
        return failures
    }

    private struct ParallelWorkItem<T: Sendable>: Sendable {
        let label: String
        let successValue: String?
        let value: T
    }

    private struct ParallelRunResult: Sendable {
        let succeeded: [String]
        let failures: [(service: String, error: Error)]
    }

    private static func parallelRun<T: Sendable>(
        _ items: [ParallelWorkItem<T>],
        work: @escaping @Sendable (T) async throws -> Void
    ) async -> ParallelRunResult {
        guard !items.isEmpty else {
            return ParallelRunResult(succeeded: [], failures: [])
        }

        var succeeded: [String] = []
        var failures: [(service: String, error: Error)] = []

        await withTaskGroup(of: (String, String?, Error?).self) { group in
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
                } else if let successValue = result.1 {
                    succeeded.append(successValue)
                }
            }
        }

        return ParallelRunResult(succeeded: succeeded, failures: failures)
    }
}
