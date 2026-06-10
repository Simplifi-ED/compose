import Foundation

package enum StatsStreamSession {
    package static func runUntilCancelled(
        projectName: String,
        serviceFilter: Set<String>?,
        mode: TerminalMode,
        policy: InterruptPolicy = .cancelOnly,
        onQuietCancel: (@Sendable () -> Void)? = nil
    ) async throws -> SignalForwarding.ExitOutcome {
        TerminalOutput.prepareStdout()

        let table = ProjectStats.defaultStatsTable()
        let renderer = StatsTableRenderer(table: table, mode: mode)

        let outcome = try await SignalForwarding.runUntilCancelled(
            policy: policy,
            terminalCleanup: { await renderer.finish() },
            body: {
                switch mode {
                case .pipe:
                    try await renderSnapshot(
                        projectName: projectName,
                        serviceFilter: serviceFilter,
                        renderer: renderer,
                        mode: mode
                    )
                case .interactive, .plain:
                    try await renderStream(
                        projectName: projectName,
                        serviceFilter: serviceFilter,
                        renderer: renderer,
                        mode: mode
                    )
                }
            }
        )

        if outcome == .cancelledQuietly {
            onQuietCancel?()
        }
        return outcome
    }

    package static func warnStatsFailures(_ names: [String], warned: inout Set<String>) {
        for name in names {
            guard warned.insert(name).inserted else { continue }
            fputs("Warning: stats unavailable for '\(name)'.\n", stderr)
        }
    }

    private static func loadContainers(
        projectName: String,
        serviceFilter: Set<String>?
    ) async throws -> [ProjectContainer] {
        let containers = try await ContainerDiscovery.projectContainers(forProject: projectName)
        return ProjectStatus.filteredContainers(from: containers, filter: serviceFilter)
    }

    private static func renderSnapshot(
        projectName: String,
        serviceFilter: Set<String>?,
        renderer: StatsTableRenderer,
        mode: TerminalMode
    ) async throws {
        let containers = try await loadContainers(projectName: projectName, serviceFilter: serviceFilter)
        var warnedFailures: Set<String> = []
        let snapshot = try await StatsCollector.collectSnapshot(for: containers)
        warnStatsFailures(snapshot.failures, warned: &warnedFailures)
        let rows = ProjectStats.rows(
            from: containers,
            previousSamples: snapshot.previous,
            currentSamples: snapshot.current
        )
        await renderer.render(rows: rows)
        if mode == .plain, !rows.isEmpty {
            print("")
        }
    }

    private static func renderStream(
        projectName: String,
        serviceFilter: Set<String>?,
        renderer: StatsTableRenderer,
        mode: TerminalMode
    ) async throws {
        var previousSamples: [String: StatsSample] = [:]
        var warnedFailures: Set<String> = []

        while !Task.isCancelled {
            let containers = try await loadContainers(projectName: projectName, serviceFilter: serviceFilter)
            let result = await StatsCollector.collect(for: containers)
            warnStatsFailures(result.failedContainerNames, warned: &warnedFailures)
            let rows = ProjectStats.rows(
                from: containers,
                previousSamples: previousSamples,
                currentSamples: result.samples
            )
            await renderer.render(rows: rows)

            if mode == .plain {
                print("")
            }

            previousSamples = result.samples
            try await Task.sleep(for: ProjectStats.sampleInterval)
        }
    }
}
