import ComposeCore
import ContainerCommands
import Foundation

extension TestRunner {
    mutating func runReadOnlyVolumeTests() throws {
        let fixturesDirectory = Self.fixtureURL("volumes-ro-compose.yml").deletingLastPathComponent()
        try runReadOnlyVolumePlannerTests(fixturesDirectory: fixturesDirectory)
        try runReadOnlyVolumeParseTests()
        try runReadOnlyVolumeConfigTests()
        try runReadOnlyVolumeDryRunTests()
        try runReadOnlyVolumeMergeTests()
        try runReadOnlyVolumePurgeTests()
        try runReadOnlyVolumeCommaOptionTests(fixturesDirectory: fixturesDirectory)
    }

    private mutating func runReadOnlyVolumePlannerTests(fixturesDirectory: URL) throws {
        let expectedDataPath = fixturesDirectory.appendingPathComponent("data").standardizedFileURL.path
        let readOnlyVolume = try ServicePlanner.volumeFlag(
            for: "./data:/mnt/data:ro",
            relativeTo: fixturesDirectory,
            projectName: "demo"
        )
        expect(readOnlyVolume == "\(expectedDataPath):/mnt/data:ro", "volume flag read-only bind mount")

        let readOnlyService = ComposeService(
            image: "docker.io/library/alpine:3.24",
            command: .string("sleep 300"),
            ports: [],
            volumes: ["./data:/mnt/data:ro"],
            environment: nil,
            containerName: nil
        )
        let readOnlyComposeFile = ComposeFile(name: nil, services: ["web": readOnlyService])
        let readOnlyContext = ServicePlanner.PlanningContext(
            composeFile: readOnlyComposeFile,
            projectName: "demo",
            composeDirectory: fixturesDirectory
        )
        let readOnlyPlan = try ServicePlanner.buildUpPlan(
            context: readOnlyContext,
            serviceName: "web",
            service: readOnlyService,
            replicaIndex: 1
        )
        let resolvedReadOnly = "\(expectedDataPath):/mnt/data:ro"
        expect(
            readOnlyPlan.runArguments.contains(resolvedReadOnly),
            "planner resolved read-only volume"
        )
        _ = try Application.ContainerRun.parse(readOnlyPlan.runArguments)
    }

    private mutating func runReadOnlyVolumeParseTests() throws {
        let fixtureURL = Self.fixtureURL("volumes-ro-compose.yml")
        let fixture = try ComposeParser.parse(fileURL: fixtureURL)
        expect(
            fixture.services["web"]?.volumes == ["./data:/mnt/data:ro"],
            "parser retains read-only volume suffix"
        )

        let commaFixture = try ComposeParser.parse(fileURL: Self.fixtureURL("volumes-ro-z-compose.yml"))
        expect(
            commaFixture.services["web"]?.volumes == ["./data:/mnt/data:ro,z"],
            "parser retains comma-separated volume options"
        )
    }

    private mutating func runReadOnlyVolumeConfigTests() throws {
        let fixtureURL = Self.fixtureURL("volumes-ro-compose.yml")
        let yaml = try ComposeConfigResolver.resolveOutput(
            fileURLs: [fixtureURL],
            activeProfiles: [],
            scaleOverrides: [:]
        )
        guard let yaml else {
            expect(false, "config export returned yaml for read-only volume fixture")
            return
        }
        expect(yaml.contains("./data:/mnt/data:ro"), "config yaml preserves read-only volume suffix")

        let commaFixtureURL = Self.fixtureURL("volumes-ro-z-compose.yml")
        let commaYAML = try ComposeConfigResolver.resolveOutput(
            fileURLs: [commaFixtureURL],
            activeProfiles: [],
            scaleOverrides: [:]
        )
        expect(
            commaYAML?.contains("./data:/mnt/data:ro,z") == true,
            "config yaml preserves comma-separated volume options"
        )
    }

    private mutating func runReadOnlyVolumeDryRunTests() throws {
        let fixtureURL = Self.fixtureURL("volumes-ro-compose.yml")
        let composeFile = try ComposeParser.parse(fileURL: fixtureURL)
        let composeDirectory = fixtureURL.deletingLastPathComponent()
        let layers = try ServicePlanner.startupLayers(
            for: composeFile,
            projectName: "demo",
            composeDirectory: composeDirectory,
            activeProfiles: [],
            scaleOverrides: [:]
        )
        guard let plan = layers.first?.first else {
            expect(false, "read-only volume dry-run produced a plan")
            return
        }
        let expectedDataPath = composeDirectory.appendingPathComponent("data").standardizedFileURL.path
        let line = DryRunManifestFormatting.formatCreate(plan)
        expect(
            line.contains("\(expectedDataPath):/mnt/data:ro"),
            "dry-run manifest includes resolved read-only volume"
        )

        let commaFixtureURL = Self.fixtureURL("volumes-ro-z-compose.yml")
        let commaFile = try ComposeParser.parse(fileURL: commaFixtureURL)
        let commaDirectory = commaFixtureURL.deletingLastPathComponent()
        let commaLayers = try ServicePlanner.startupLayers(
            for: commaFile,
            projectName: "demo",
            composeDirectory: commaDirectory,
            activeProfiles: [],
            scaleOverrides: [:]
        )
        guard let commaPlan = commaLayers.first?.first else {
            expect(false, "comma-option volume dry-run produced a plan")
            return
        }
        let commaLine = DryRunManifestFormatting.formatCreate(commaPlan)
        expect(
            commaLine.contains("\(expectedDataPath):/mnt/data:ro,z"),
            "dry-run manifest includes resolved comma-separated volume options"
        )
    }

    private mutating func runReadOnlyVolumeMergeTests() throws {
        let mergeDirectory = Self.fixtureURL("merge/base.yml").deletingLastPathComponent()
        let baseURL = mergeDirectory.appendingPathComponent("base.yml")
        let overrideURL = mergeDirectory.appendingPathComponent("override-volume-ro.yml")
        let merged = try ComposeParser.parse(fileURLs: [baseURL, overrideURL])
        expect(
            merged.services["web"]?.volumes == ["./other:/mnt/config:ro"],
            "merge replaces volume mount path with read-only override"
        )

        let roBaseURL = mergeDirectory.appendingPathComponent("base-ro-volume.yml")
        let writableOverrideURL = mergeDirectory.appendingPathComponent("override-volume-writable.yml")
        let writableMerged = try ComposeParser.parse(fileURLs: [roBaseURL, writableOverrideURL])
        expect(
            writableMerged.services["web"]?.volumes == ["./other:/mnt/config"],
            "merge replaces read-only volume with writable override on same mount path"
        )
    }

    private mutating func runReadOnlyVolumePurgeTests() throws {
        let fixture = try ComposeParser.parse(fileURL: Self.fixtureURL("volumes-ro-compose.yml"))
        let fixtureDirectory = Self.fixtureURL("volumes-ro-compose.yml").deletingLastPathComponent()
        let paths = BindMountPurge.collectPurgeablePaths(
            composeFile: fixture,
            composeDirectory: fixtureDirectory,
            serviceNames: ["web"]
        )
        let expectedDataPath = fixtureDirectory
            .appendingPathComponent("data")
            .standardizedFileURL
            .path
        expect(paths == [expectedDataPath], "purge ignores read-only suffix on bind-mount paths")
    }

    private mutating func runReadOnlyVolumeCommaOptionTests(fixturesDirectory: URL) throws {
        let expectedDataPath = fixturesDirectory.appendingPathComponent("data").standardizedFileURL.path
        let commaVolume = try ServicePlanner.volumeFlag(
            for: "./data:/mnt/data:ro,z",
            relativeTo: fixturesDirectory,
            projectName: "demo"
        )
        expect(
            commaVolume == "\(expectedDataPath):/mnt/data:ro,z",
            "volume flag preserves comma-separated read-only options"
        )

        let reversedVolume = try ServicePlanner.volumeFlag(
            for: "./data:/mnt/data:z,ro",
            relativeTo: fixturesDirectory,
            projectName: "demo"
        )
        expect(
            reversedVolume == "\(expectedDataPath):/mnt/data:z,ro",
            "volume flag preserves comma option order"
        )
        _ = try Application.ContainerRun.parse(["-v", commaVolume, "docker.io/library/alpine:3.24"])

        expectComposeError(
            "unsupported comma volume option",
            matching: { if case .unsupportedVolumeOption = $0 { true } else { false } },
            body: {
                _ = try ServicePlanner.volumeFlag(
                    for: "./data:/mnt/data:ro,invalid",
                    relativeTo: fixturesDirectory,
                    projectName: "demo"
                )
            }
        )
    }
}
