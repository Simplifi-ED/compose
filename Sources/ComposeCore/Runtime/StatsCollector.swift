import ContainerAPIClient
import ContainerResource
import Foundation

package struct StatsCollectResult: Sendable {
    package let samples: [String: StatsSample]
    package let failedContainerNames: [String]

    package init(samples: [String: StatsSample], failedContainerNames: [String]) {
        self.samples = samples
        self.failedContainerNames = failedContainerNames
    }
}

package struct StatsSnapshotResult: Sendable {
    package let previous: [String: StatsSample]
    package let current: [String: StatsSample]
    package let failures: [String]

    package init(
        previous: [String: StatsSample],
        current: [String: StatsSample],
        failures: [String]
    ) {
        self.previous = previous
        self.current = current
        self.failures = failures
    }
}

/// Fetches per-container resource stats for running project containers.
package enum StatsCollector {
    private enum CollectOutcome: Sendable {
        case sample(String, StatsSample)
        case failure(String)
    }

    package static func collect(
        for containers: [ProjectContainer],
        client: ContainerClient = ContainerClient()
    ) async -> StatsCollectResult {
        let running = containers.filter { $0.status == .running }
        guard !running.isEmpty else {
            return StatsCollectResult(samples: [:], failedContainerNames: [])
        }

        let collectedAt = ContinuousClock.now
        return await withTaskGroup(of: CollectOutcome?.self) { group in
            for container in running {
                group.addTask {
                    guard !Task.isCancelled else { return nil }
                    do {
                        let stats = try await client.stats(id: container.name)
                        guard !Task.isCancelled else { return nil }
                        return .sample(
                            container.name,
                            StatsSample(stats: stats, collectedAt: collectedAt)
                        )
                    } catch {
                        return .failure(container.name)
                    }
                }
            }

            var samples: [String: StatsSample] = [:]
            var failures: [String] = []
            for await outcome in group {
                guard !Task.isCancelled else { break }
                guard let outcome else { continue }
                switch outcome {
                case .sample(let name, let sample):
                    samples[name] = sample
                case .failure(let name):
                    failures.append(name)
                }
            }
            return StatsCollectResult(samples: samples, failedContainerNames: failures)
        }
    }

    /// Waits one sample interval, then collects a second sample for pipe-mode snapshots.
    package static func collectSnapshot(
        for containers: [ProjectContainer],
        sampleInterval: Duration = ProjectStats.defaultSampleInterval,
        client: ContainerClient = ContainerClient()
    ) async throws -> StatsSnapshotResult {
        let first = await collect(for: containers, client: client)
        if !first.samples.isEmpty {
            try await Task.sleep(for: sampleInterval)
        }
        let second = await collect(for: containers, client: client)
        let failures = first.failedContainerNames + second.failedContainerNames
        return StatsSnapshotResult(
            previous: first.samples,
            current: second.samples,
            failures: failures
        )
    }
}
