import ComposeCore
import Foundation

extension TestRunner {
    mutating func runNamedVolumeShutdownTests() throws {
        try runNamedVolumeDryRunTests()
        try runNamedVolumeDownRemovalTests()
    }

    private mutating func runNamedVolumeDryRunTests() throws {
        expect(
            DryRunManifestFormatting.formatVolumeCreate(name: "demo_mydata")
                == "[DRY-RUN] create volume \"demo_mydata\"",
            "dry-run volume create line"
        )
        expect(
            DryRunManifestFormatting.formatVolumeRemove(name: "demo_mydata")
                == "[DRY-RUN] remove volume \"demo_mydata\"",
            "dry-run volume remove line"
        )

        let fixtureURL = Self.fixtureURL("named-volumes-compose.yml")
        let fixture = try ComposeParser.parse(fileURL: fixtureURL)
        let layers = try ServicePlanner.startupLayers(
            for: fixture,
            projectName: "demo",
            composeDirectory: fixtureURL.deletingLastPathComponent()
        )
        guard let plan = layers.first?.first else {
            expect(false, "volumes dry-run produced a plan")
            return
        }
        expect(
            DryRunManifestFormatting.formatCreate(plan).contains("demo_mydata:/app/data"),
            "dry-run container line includes named volume mount"
        )

        let lines = blockingAwait {
            let manifest = DryRunManifest()
            await manifest.recordVolumeCreate(name: "demo_mydata")
            await manifest.setUpWaveIndex(0)
            await manifest.recordCreate(plan)
            return await manifest.sortedLines()
        }
        expect(lines.count == 2, "dry-run manifest records volume and container")
        expect(
            lines.first == "[DRY-RUN] create volume \"demo_mydata\"",
            "volume create sorts before container create"
        )
    }

    private mutating func runNamedVolumeDownRemovalTests() throws {
        let fixtureURL = Self.fixtureURL("named-volumes-compose.yml")
        let fixture = try ComposeParser.parse(fileURL: fixtureURL)
        let context = ProjectOptions.LabelCommandContext(
            projectName: "demo",
            composeFile: fixture,
            fileURLs: [fixtureURL]
        )
        let client = DiscoveredContainer(name: "demo_client_1", serviceName: "client")
        let server = DiscoveredContainer(name: "demo_server_1", serviceName: "server")

        let fullTeardown = try DownShutdown.volumeRemovalPlans(
            context: context,
            discovered: [client, server],
            teardownContainers: [client, server]
        )
        expect(fullTeardown.map(\.runtimeName) == ["demo_mydata"], "full down -v removes project volume")

        let partialTeardown = try DownShutdown.volumeRemovalPlans(
            context: context,
            discovered: [client, server],
            teardownContainers: [client]
        )
        expect(partialTeardown.isEmpty, "volume kept while another member service still runs")

        let noComposeFile = try DownShutdown.volumeRemovalPlans(
            context: ProjectOptions.LabelCommandContext(
                projectName: "demo",
                composeFile: nil,
                fileURLs: nil
            ),
            discovered: [client],
            teardownContainers: [client]
        )
        expect(noComposeFile.isEmpty, "no volume removal without compose file")

        let fullVolumePlans = try DownShutdown.volumeRemovalPlans(
            context: context,
            discovered: [client, server],
            teardownContainers: [client, server]
        )
        let downDryRunLines = blockingAwait {
            let manifest = DryRunManifest()
            await manifest.recordVolumeRemovals(names: fullVolumePlans.map(\.runtimeName))
            return await manifest.sortedLines()
        }
        expect(
            downDryRunLines.contains("[DRY-RUN] remove volume \"demo_mydata\""),
            "down dry-run records named volume removal"
        )
    }
}
