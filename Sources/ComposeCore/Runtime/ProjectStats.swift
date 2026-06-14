import ContainerResource
import Foundation

package struct ProjectStatsRow: Sendable, Equatable {
    package let name: String
    package let service: String
    package let cpu: String
    package let memory: String
    package let network: String
    package let blockIO: String
    package let pids: String

    package var cells: [String] { [name, service, cpu, memory, network, blockIO, pids] }

    package init(
        name: String,
        service: String,
        cpu: String,
        memory: String,
        network: String,
        blockIO: String,
        pids: String
    ) {
        self.name = name
        self.service = service
        self.cpu = cpu
        self.memory = memory
        self.network = network
        self.blockIO = blockIO
        self.pids = pids
    }
}

/// Per-container stats sample used for CPU delta calculation across refresh ticks.
package struct StatsSample: Sendable {
    package let stats: ContainerStats
    package let collectedAt: ContinuousClock.Instant

    package init(stats: ContainerStats, collectedAt: ContinuousClock.Instant) {
        self.stats = stats
        self.collectedAt = collectedAt
    }
}

package enum ProjectStats {
    package static let notAvailable = StatsFormatting.notAvailable
    package static let defaultSampleIntervalSeconds = 2
    package static let defaultSampleInterval: Duration = .seconds(defaultSampleIntervalSeconds)

    package static func rows(
        from containers: [ProjectContainer],
        previousSamples: [String: StatsSample],
        currentSamples: [String: StatsSample]
    ) -> [ProjectStatsRow] {
        containers.map { container in
            row(
                for: container,
                previous: previousSamples[container.name],
                current: currentSamples[container.name]
            )
        }
    }

    package static func row(
        for container: ProjectContainer,
        previous: StatsSample?,
        current: StatsSample?
    ) -> ProjectStatsRow {
        guard container.status == .running, let current else {
            return unavailableRow(for: container)
        }

        let stats = current.stats

        return ProjectStatsRow(
            name: container.name,
            service: container.serviceName ?? "",
            cpu: StatsFormatting.formatCPU(previous: previous, current: current),
            memory: StatsFormatting.formatMemory(usage: stats.memoryUsageBytes, limit: stats.memoryLimitBytes),
            network: StatsFormatting.formatPair(
                received: stats.networkRxBytes,
                transmitted: stats.networkTxBytes
            ),
            blockIO: StatsFormatting.formatPair(
                received: stats.blockReadBytes,
                transmitted: stats.blockWriteBytes
            ),
            pids: StatsFormatting.formatPIDs(stats.numProcesses)
        )
    }

    package static func defaultStatsTable() -> TableFormat {
        TableFormat(columns: [
            TableFormat.Column(title: "NAME", width: 24),
            TableFormat.Column(title: "SERVICE", width: 12),
            TableFormat.Column(title: "CPU %", width: 8, alignment: .right),
            TableFormat.Column(title: "MEM USAGE / LIMIT", width: 20),
            TableFormat.Column(title: "NET RX/TX", width: 18),
            TableFormat.Column(title: "BLOCK I/O", width: 18),
            TableFormat.Column(title: "PIDS", width: 6, alignment: .right)
        ])
    }

    private static func unavailableRow(for container: ProjectContainer) -> ProjectStatsRow {
        ProjectStatsRow(
            name: container.name,
            service: container.serviceName ?? "",
            cpu: notAvailable,
            memory: notAvailable,
            network: notAvailable,
            blockIO: notAvailable,
            pids: notAvailable
        )
    }
}
