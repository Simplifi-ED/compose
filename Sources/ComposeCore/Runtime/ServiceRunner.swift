import ContainerCommands
import Foundation

public enum ServiceRunner {
    public static func up(plans: [ServicePlan]) async throws {
        try await up(layers: [plans])
    }

    public static func up(layers: [[ServicePlan]]) async throws {
        for layer in layers {
            try await runInParallel(layer.map { (label: $0.serviceName, value: $0) }) { plan in
                let command = try Application.ContainerRun.parse(plan.runArguments)
                try await command.run()
            }
        }
    }

    public static func down(containers: [DiscoveredContainer]) async throws {
        try await runInParallel(containers.map { (label: $0.name, value: $0.name) }) { name in
            try await ContainerTeardown.teardown(id: name)
        }
    }

    private static func runInParallel<T: Sendable>(
        _ items: [(label: String, value: T)],
        work: @escaping @Sendable (T) async throws -> Void
    ) async throws {
        guard !items.isEmpty else { return }

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
            }
        }

        if !failures.isEmpty {
            throw ComposeError.multipleServiceFailures(failures)
        }
    }
}
