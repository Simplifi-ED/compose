import ComposeCore
import Foundation

extension TestRunner {
    mutating func runDryRunUpTests() throws {
        let fixtureURL = Self.fixtureURL("minimal-compose.yml")
        let composeFile = try ComposeParser.parse(fileURL: fixtureURL)
        let composeDirectory = fixtureURL.deletingLastPathComponent()
        let layers = try ServicePlanner.startupLayers(
            for: composeFile,
            projectName: "demo",
            composeDirectory: composeDirectory,
            activeProfiles: [],
            scaleOverrides: [:]
        )
        let manifest = DryRunManifest()
        let (completed, lines) = dryRunUpResult(layers: layers, manifest: manifest)
        let plan = layers[0][0]
        expect(completed, "dry-run up completes")
        expect(lines.count == 1, "dry-run up single create line")
        expect(
            lines[0] == DryRunManifestFormatting.formatCreate(plan),
            "dry-run up create manifest"
        )
        expect(lines[0].contains("detach=true"), "dry-run up detached create")
    }

    mutating func runDryRunHealthWaitTests() throws {
        let services = Self.healthFixtureServices(retries: 1)
        let composeFile = ComposeFile(name: nil, services: services)
        let composeDirectory = Self.fixtureURL("minimal-compose.yml").deletingLastPathComponent()
        let layers = try ServicePlanner.startupLayers(
            for: composeFile,
            projectName: "demo",
            composeDirectory: composeDirectory,
            activeProfiles: [],
            scaleOverrides: [:]
        )
        let healthContext = HealthWaitContext(services: services, projectName: "demo")
        let manifest = DryRunManifest()
        let (completed, lines) = dryRunUpResult(
            layers: layers,
            healthContext: healthContext,
            manifest: manifest
        )
        expect(completed, "dry-run health orchestration completes")
        expect(lines.count == 3, "dry-run health creates and wait lines")
        expect(
            lines[0].hasPrefix("[DRY-RUN] create container \"demo_db_1\""),
            "dry-run health first wave create"
        )
        expect(
            lines[1].hasPrefix("[DRY-RUN] wait for service \"db\""),
            "dry-run health wait line"
        )
        expect(
            lines[2].hasPrefix("[DRY-RUN] create container \"demo_web_1\""),
            "dry-run health second wave create"
        )
    }

    mutating func runDryRunScaleTests() throws {
        let fixtureURL = Self.fixtureURL("scale-compose.yml")
        let composeFile = try ComposeParser.parse(fileURL: fixtureURL)
        let composeDirectory = fixtureURL.deletingLastPathComponent()
        let layers = try ServicePlanner.startupLayers(
            for: composeFile,
            projectName: "demo",
            composeDirectory: composeDirectory,
            activeProfiles: [],
            scaleOverrides: [:]
        )
        let manifest = DryRunManifest()
        let (completed, lines) = dryRunUpResult(layers: layers, manifest: manifest)
        expect(completed, "dry-run scale up completes")
        expect(lines.count == 3, "dry-run scale creates three containers")
        expect(
            lines.contains(where: { $0.contains("\"demo_web_1\"") }),
            "dry-run scale web replica 1"
        )
        expect(
            lines.contains(where: { $0.contains("\"demo_web_2\"") }),
            "dry-run scale web replica 2"
        )
        expect(
            lines.contains(where: { $0.contains("\"demo_db_1\"") }),
            "dry-run scale db container"
        )
    }
}
