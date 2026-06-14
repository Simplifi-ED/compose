import ComposeCore
import ContainerResource
import Foundation

extension TestRunner {
    mutating func runPauseTests() throws {
        runPauseTargetSelectionTests()
        runPauseSummaryTests()
        runPauseDryRunTests()
        runPauseParallelTests()
        runPauseSignalRoutingTests()
        try runPauseProfileFilterTests()
    }

    private mutating func runPauseTargetSelectionTests() {
        let running = ProjectContainer(
            name: "demo_web_1",
            serviceName: "web",
            status: .running,
            publishedPorts: []
        )
        let stopped = ProjectContainer(
            name: "demo_db_1",
            serviceName: "db",
            status: .stopped,
            publishedPorts: []
        )
        let pauseTargets = ContainerLifecycle.targetsForPause(from: [running, stopped])
        expect(pauseTargets.map(\.name) == ["demo_web_1"], "pause selects running containers only")

        let unpauseTargets = ContainerLifecycle.targetsForUnpause(from: [running, stopped])
        expect(unpauseTargets.map(\.name) == ["demo_web_1"], "unpause selects running until .paused exists")
    }

    private mutating func runPauseSummaryTests() {
        expect(
            PauseSummary.emptyMessage(operation: .pause) == "No running containers to pause.",
            "pause empty message"
        )
        expect(
            PauseSummary.emptyMessage(operation: .unpause) == "No paused containers to unpause.",
            "unpause empty message"
        )
        expect(
            PauseSummary.summaryLine(operation: .pause, names: ["demo_web_1"])
                == "Paused 1 container: demo_web_1",
            "pause single summary"
        )
        expect(
            PauseSummary.summaryLine(operation: .pause, names: ["demo_a", "demo_b"])
                == "Paused 2 containers: demo_a, demo_b",
            "pause plural summary"
        )
    }

    private mutating func runPauseDryRunTests() {
        expect(
            DryRunManifestFormatting.formatPause("demo_web_1")
                == "[DRY-RUN] pause container \"demo_web_1\"",
            "dry-run pause format"
        )
        expect(
            DryRunManifestFormatting.formatUnpause("demo_web_1")
                == "[DRY-RUN] unpause container \"demo_web_1\"",
            "dry-run unpause format"
        )

        let lines = dryRunManifestLines(manifest: DryRunManifest()) { manifest in
            await manifest.recordPause("demo_web_1")
            await manifest.recordPause("demo_db_1")
        }
        expect(lines.count == 2, "dry-run pause records all targets")
        expect(lines[0] == "[DRY-RUN] pause container \"demo_db_1\"", "dry-run pause sorted by name")
        expect(lines[1] == "[DRY-RUN] pause container \"demo_web_1\"", "dry-run pause sorted by name")

        let machineLines = dryRunManifestLines(manifest: DryRunManifest(machineName: "dev")) { manifest in
            await manifest.recordPause("demo_web_1")
        }
        expect(
            machineLines[0] == "[DRY-RUN] machine=dev pause container \"demo_web_1\"",
            "dry-run pause machine prefix"
        )
    }

    private mutating func runPauseParallelTests() {
        let affected = blockingAwait {
            try? await ContainerLifecycle.apply(
                names: ["a", "b", "c"],
                operation: .pause,
                execution: WaveExecutionPolicy(maxConcurrent: 1),
                machineContext: .applicationSandbox,
                dryRunManifest: DryRunManifest()
            )
        }
        expect(affected == ["a", "b", "c"], "dry-run apply returns all target names")

        let peak = blockingAwait {
            await ServiceRunner.parallelRunPeakConcurrency(maxConcurrent: 1, itemCount: 4)
        }
        expect(peak == 1, "pause batch can throttle via WaveExecutionPolicy")
    }

    private mutating func runPauseSignalRoutingTests() {
        expect(
            ComposeContainerGateway.pauseSignal == "SIGSTOP",
            "pause routes through kill with SIGSTOP"
        )
        expect(
            ComposeContainerGateway.unpauseSignal == "SIGCONT",
            "unpause routes through kill with SIGCONT"
        )
    }

    private mutating func runPauseProfileFilterTests() throws {
        let fixture = try ComposeParser.parse(fileURL: Self.fixtureURL("profiles-compose.yml"))
        let context = ProjectOptions.LabelCommandContext(
            projectName: "demo",
            composeFile: fixture,
            fileURLs: [Self.fixtureURL("profiles-compose.yml")]
        )
        let discovered = [
            DiscoveredContainer(name: "demo_web", serviceName: "web"),
            DiscoveredContainer(name: "demo_debugger", serviceName: "debugger"),
            DiscoveredContainer(name: "demo_metrics", serviceName: "metrics")
        ]
        let projectContainers = [
            ProjectContainer(name: "demo_web", serviceName: "web", status: .running, publishedPorts: []),
            ProjectContainer(
                name: "demo_debugger",
                serviceName: "debugger",
                status: .running,
                publishedPorts: []
            ),
            ProjectContainer(
                name: "demo_metrics",
                serviceName: "metrics",
                status: .running,
                publishedPorts: []
            )
        ]

        let filtered = try ContainerLifecycle.filteredTargetNames(
            discovered: discovered,
            projectContainers: projectContainers,
            scope: ProjectPauseScope(
                context: context,
                profileFilterRequested: true,
                activeProfiles: ["debug"],
                tearsDownAll: false
            ),
            operation: .pause
        )
        expect(filtered == ["demo_debugger", "demo_web"], "profile filter scopes pause targets")
    }
}
