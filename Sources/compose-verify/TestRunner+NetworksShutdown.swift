import ComposeCore
import Foundation

extension TestRunner {
    mutating func runNetworkShutdownTests() throws {
        try runNetworkDryRunTests()
        try runNetworkDownRemovalTests()
    }

    private mutating func runNetworkDryRunTests() throws {
        expect(
            DryRunManifestFormatting.formatNetworkCreate(name: "demo_backend")
                == "[DRY-RUN] create network \"demo_backend\"",
            "dry-run network create line"
        )
        expect(
            DryRunManifestFormatting.formatNetworkRemove(name: "demo_backend")
                == "[DRY-RUN] remove network \"demo_backend\"",
            "dry-run network remove line"
        )

        let fixtureURL = Self.fixtureURL("networks-compose.yml")
        let fixture = try ComposeParser.parse(fileURL: fixtureURL)
        let layers = try ServicePlanner.startupLayers(
            for: fixture,
            projectName: "demo",
            composeDirectory: fixtureURL.deletingLastPathComponent()
        )
        guard let plan = layers.first?.first else {
            expect(false, "networks dry-run produced a plan")
            return
        }
        expect(
            DryRunManifestFormatting.formatCreate(plan).contains("networks=[\"demo_backend\"]"),
            "dry-run container line includes networks"
        )

        let lines = blockingAwait {
            let manifest = DryRunManifest()
            await manifest.recordNetworkCreate(name: "demo_backend")
            await manifest.setUpWaveIndex(0)
            await manifest.recordCreate(plan)
            return await manifest.sortedLines()
        }
        expect(lines.count == 2, "dry-run manifest records network and container")
        expect(
            lines.first == "[DRY-RUN] create network \"demo_backend\"",
            "network create sorts before container create"
        )
    }

    private mutating func runNetworkDownRemovalTests() throws {
        let fixtureURL = Self.fixtureURL("networks-compose.yml")
        let fixture = try ComposeParser.parse(fileURL: fixtureURL)
        let context = ProjectOptions.LabelCommandContext(
            projectName: "demo",
            composeFile: fixture,
            fileURLs: [fixtureURL]
        )
        let client = DiscoveredContainer(name: "demo_client_1", serviceName: "client")
        let server = DiscoveredContainer(name: "demo_server_1", serviceName: "server")

        let fullTeardown = try DownShutdown.networkRemovalPlans(
            context: context,
            discovered: [client, server],
            teardownContainers: [client, server]
        )
        expect(fullTeardown.map(\.runtimeName) == ["demo_backend"], "full down removes project network")

        let partialTeardown = try DownShutdown.networkRemovalPlans(
            context: context,
            discovered: [client, server],
            teardownContainers: [client]
        )
        expect(partialTeardown.isEmpty, "network kept while another member service still runs")

        let noComposeFile = try DownShutdown.networkRemovalPlans(
            context: ProjectOptions.LabelCommandContext(
                projectName: "demo",
                composeFile: nil,
                fileURLs: nil
            ),
            discovered: [client],
            teardownContainers: [client]
        )
        expect(noComposeFile.isEmpty, "no network removal without compose file")

        let profileFixtureURL = Self.fixtureURL("networks-profile-bad-ref-compose.yml")
        let profileFixture = try ComposeParser.parse(fileURL: profileFixtureURL)
        let profileContext = ProjectOptions.LabelCommandContext(
            projectName: "demo",
            composeFile: profileFixture,
            fileURLs: [profileFixtureURL]
        )
        let web = DiscoveredContainer(name: "demo_web_1", serviceName: "web")
        let profileTeardown = try DownShutdown.networkRemovalPlans(
            context: profileContext,
            discovered: [web],
            teardownContainers: [web]
        )
        expect(
            profileTeardown.map(\.runtimeName) == ["demo_backend"],
            "down ignores profile-gated service with invalid network reference"
        )
    }
}
