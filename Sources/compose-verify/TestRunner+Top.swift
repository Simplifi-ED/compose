import ComposeCore
import ContainerResource
import Foundation

extension TestRunner {
    mutating func runTopTests() {
        runTopCPUCalculationTests()
        runTopByteFormatTests()
        runTopRowBuildTests()
        runTopTableOutputTests()
        runTopRendererTests()
        runTopStatsFailureWarningTests()
        runTopSignalPolicyTests()
    }

    private mutating func runTopCPUCalculationTests() {
        let halfCore = StatsFormatting.calculateCPUPercent(
            cpuUsage1: .seconds(0),
            cpuUsage2: .seconds(1),
            timeInterval: .seconds(2)
        )
        expect(abs(halfCore - 50.0) < 0.01, "one second CPU over two second interval is 50%")

        let idle = StatsFormatting.calculateCPUPercent(
            cpuUsage1: .seconds(1),
            cpuUsage2: .seconds(1),
            timeInterval: .seconds(1)
        )
        expect(idle == 0, "unchanged CPU usage yields 0%")

        let reversed = StatsFormatting.calculateCPUPercent(
            cpuUsage1: .seconds(2),
            cpuUsage2: .seconds(1),
            timeInterval: .seconds(1)
        )
        expect(reversed == 0, "decreasing CPU counter yields 0%")
    }

    private mutating func runTopByteFormatTests() {
        expect(StatsFormatting.formatBytes(512) == "512 bytes", "sub-KiB bytes label")
        expect(StatsFormatting.formatBytes(1_024) == "1 kB", "KiB boundary")
        expect(StatsFormatting.formatBytes(1_048_576) == "1 MB", "MiB boundary")
        expect(StatsFormatting.formatBytes(1_073_741_824) == "1 GB", "GiB boundary")
    }

    private mutating func runTopRowBuildTests() {
        runTopStoppedRowTests()
        runTopRunningRowTests()
        runTopFilterReuseTests()
    }

    private mutating func runTopStoppedRowTests() {
        let stopped = ProjectContainer(
            name: "demo_db",
            serviceName: "db",
            status: .stopped,
            publishedPorts: []
        )
        let unavailable = ProjectStats.row(for: stopped, previous: nil, current: nil)
        expect(unavailable.cpu == ProjectStats.notAvailable, "stopped container shows unavailable CPU")
        expect(unavailable.pids == ProjectStats.notAvailable, "stopped container shows unavailable PIDs")
    }

    private mutating func runTopRunningRowTests() {
        let running = ProjectContainer(
            name: "demo_web",
            serviceName: "web",
            status: .running,
            publishedPorts: []
        )
        let now = ContinuousClock.now
        let current = StatsSample(
            stats: ContainerStats(
                id: "demo_web",
                memoryUsageBytes: 1_048_576,
                memoryLimitBytes: 2_097_152,
                cpuUsageUsec: 1_000_000,
                networkRxBytes: 1_024,
                networkTxBytes: 2_048,
                blockReadBytes: 512,
                blockWriteBytes: 1_024,
                numProcesses: 3
            ),
            collectedAt: now
        )
        let previous = StatsSample(
            stats: ContainerStats(
                id: "demo_web",
                memoryUsageBytes: 1_048_576,
                memoryLimitBytes: 2_097_152,
                cpuUsageUsec: 500_000,
                networkRxBytes: 512,
                networkTxBytes: 1_024,
                blockReadBytes: 256,
                blockWriteBytes: 512,
                numProcesses: 3
            ),
            collectedAt: now - .seconds(1)
        )

        let row = ProjectStats.row(for: running, previous: previous, current: current)
        expect(row.name == "demo_web", "stats row uses container name")
        expect(row.service == "web", "stats row uses compose service")
        expect(row.cpu.contains("%"), "CPU column includes percent sign")
        expect(row.memory.contains(" / "), "memory column shows usage and limit")
        expect(row.pids == "3", "PIDs formatted without grouping")

        let firstTick = ProjectStats.row(for: running, previous: nil, current: current)
        expect(firstTick.cpu == ProjectStats.notAvailable, "first tick lacks CPU delta")
    }

    private mutating func runTopFilterReuseTests() {
        let running = ProjectContainer(
            name: "demo_web",
            serviceName: "web",
            status: .running,
            publishedPorts: []
        )
        let stopped = ProjectContainer(
            name: "demo_db",
            serviceName: "db",
            status: .stopped,
            publishedPorts: []
        )
        let containers = [running, stopped]
        let rows = ProjectStats.rows(from: containers, previousSamples: [:], currentSamples: [:])
        expect(rows.count == 2, "rows include all filtered containers")
        expect(rows[1].cpu == ProjectStats.notAvailable, "stopped row in batch is unavailable")

        let webOnly = ProjectStatus.filteredContainers(from: containers, filter: ["web"])
        expect(webOnly.count == 1, "top reuses ProjectStatus service filter")
    }

    private mutating func runTopTableOutputTests() {
        let table = ProjectStats.defaultStatsTable()
        let header = table.formatHeader(mode: .plain)
        expect(header.contains("NAME"), "stats header includes NAME")
        expect(header.contains("CPU %"), "stats header includes CPU %")
        expect(header.contains("MEM USAGE / LIMIT"), "stats header includes memory column")

        let row = ProjectStatsRow(
            name: "demo_web",
            service: "web",
            cpu: "12.34%",
            memory: "1 MB / 2 MB",
            network: "1 kB / 2 kB",
            blockIO: "512 bytes / 1 kB",
            pids: "3"
        )
        let formatted = table.formatRow(row.cells)
        expect(formatted.contains("demo_web"), "formatted row includes container name")
        expect(formatted.contains("12.34%"), "formatted row includes CPU value")
        expect(table.columns.count == 7, "stats table has seven columns")
    }

    private mutating func runTopRendererTests() {
        let buffer = LineBuffer()
        let table = ProjectStats.defaultStatsTable()
        let row = ProjectStatsRow(
            name: "demo_web",
            service: "web",
            cpu: "1.00%",
            memory: "1 MB / 2 MB",
            network: "1 kB / 2 kB",
            blockIO: "512 bytes / 1 kB",
            pids: "3"
        )

        blockingAwait {
            let renderer = StatsTableRenderer(table: table, mode: .interactive) { buffer.append($0) }
            await renderer.render(rows: [row])
            await renderer.render(rows: [row])
            await renderer.finish()
        }

        let output = buffer.lines.joined()
        expect(output.contains("\r\u{001B}[K"), "interactive stats uses clear-line redraw")
        expect(output.contains("\u{001B}[2A"), "interactive stats moves cursor up on refresh")
        expect(stripANSI(output).contains("demo_web"), "interactive stats renders container row")
    }

    private mutating func runTopStatsFailureWarningTests() {
        var warned: Set<String> = []
        StatsStreamSession.warnStatsFailures(["demo_web"], warned: &warned)
        StatsStreamSession.warnStatsFailures(["demo_web", "demo_db"], warned: &warned)
        expect(warned == ["demo_web", "demo_db"], "stats failure warnings deduplicate per container")
    }

    private mutating func runTopSignalPolicyTests() {
        let outcome = blockingAwait {
            try? await SignalForwarding.interruptedOutcome(policy: .cancelOnly, signal: InterruptSignal(number: 2))
        }
        expect(outcome == .cancelledQuietly, "top interrupt policy exits quietly")
    }
}
