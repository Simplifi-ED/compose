import ContainerResource
import Foundation

/// Display formatting for `ContainerResource.ContainerStats`.
///
/// CPU delta math intentionally mirrors upstream
/// `ContainerCommands.Application.ContainerStats.calculateCPUPercent` and
/// `formatBytes` in `container/Sources/ContainerCommands/Container/ContainerStats.swift`.
/// Those helpers are `internal` to `ContainerCommands`; compose cannot call them until
/// Apple exports equivalent APIs on `ContainerResource` (tracked as upstream reuse debt).
///
/// Intentional divergences:
/// - Byte counts use `FormatStyle.byteCount` (binary) instead of upstream `%.2f GiB/KiB` strings.
/// - CPU intervals use measured `ContinuousClock` deltas (~1s) instead of a fixed 2s window.
package enum StatsFormatting {
    package static let notAvailable = "--"

    private static let pidStyle = IntegerFormatStyle<Int>().grouping(.never)

    /// Port of upstream `Application.ContainerStats.calculateCPUPercent`.
    package static func calculateCPUPercent(
        cpuUsage1: Duration,
        cpuUsage2: Duration,
        timeInterval: Duration
    ) -> Double {
        let cpuDelta = cpuUsage2 > cpuUsage1 ? cpuUsage2 - cpuUsage1 : .seconds(0)
        return (cpuDelta / timeInterval) * 100.0
    }

    package static func formatBytes(_ bytes: UInt64) -> String {
        bytes.formatted(.byteCount(style: .binary))
    }

    package static func formatCPU(
        previous: StatsSample?,
        current: StatsSample
    ) -> String {
        guard let previous,
              let cpu1 = previous.stats.cpuUsageUsec,
              let cpu2 = current.stats.cpuUsageUsec
        else {
            return notAvailable
        }

        let interval = current.collectedAt - previous.collectedAt
        let percent = calculateCPUPercent(
            cpuUsage1: .microseconds(cpu1),
            cpuUsage2: .microseconds(cpu2),
            timeInterval: interval
        )
        return (percent / 100.0).formatted(.percent.precision(.fractionLength(2)))
    }

    package static func formatMemory(usage: UInt64?, limit: UInt64?) -> String {
        let usageStr = usage.map(formatBytes) ?? notAvailable
        let limitStr = limit.map(formatBytes) ?? notAvailable
        return "\(usageStr) / \(limitStr)"
    }

    package static func formatPair(received: UInt64?, transmitted: UInt64?) -> String {
        let receivedStr = received.map(formatBytes) ?? notAvailable
        let transmittedStr = transmitted.map(formatBytes) ?? notAvailable
        return "\(receivedStr) / \(transmittedStr)"
    }

    package static func formatPIDs(_ count: UInt64?) -> String {
        guard let count else { return notAvailable }
        return Int(count).formatted(pidStyle)
    }
}
