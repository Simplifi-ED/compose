import ComposeCore
import ContainerCommands
import Foundation

extension TestRunner {
    mutating func runNamedVolumeTests() throws {
        try runNamedVolumeParserTests()
        try runNamedVolumeParserErrorTests()
        try runNamedVolumeNameTests()
        try runNamedVolumePlanningTests()
        try runNamedVolumePlannerArgumentTests()
        try runNamedVolumeMergeTests()
        try runNamedVolumeConfigTests()
        try runNamedVolumeShutdownTests()
        runNamedVolumeLabelTests()
        try runNamedVolumeMachineTests()
    }

    private mutating func runNamedVolumeParserTests() throws {
        let fixture = try ComposeParser.parse(fileURL: Self.fixtureURL("named-volumes-compose.yml"))
        expect(fixture.volumes.keys.sorted() == ["mydata"], "root volumes decode")
        expect(fixture.services["client"]?.volumes == ["mydata:/app/data"], "service named volume decode")
        expect(fixture.services["server"]?.volumes == ["mydata:/var/data"], "second service named volume decode")
        let minimal = try ComposeParser.parse(fileURL: Self.fixtureURL("minimal-compose.yml"))
        expect(minimal.volumes.isEmpty, "no volumes block decodes to empty map")
    }

    private mutating func runNamedVolumeParserErrorTests() throws {
        expectComposeError(
            "external volume",
            matching: { if case .unsupportedExternalVolume = $0 { true } else { false } },
            body: {
                _ = try ComposeParser.parse(fileURL: Self.fixtureURL("volumes-external-compose.yml"))
            }
        )
    }

    private mutating func runNamedVolumeNameTests() throws {
        let runtimeName = try VolumePlanning.runtimeVolumeName(projectName: "demo", volumeName: "mydata")
        expect(runtimeName == "demo_mydata", "runtime volume name")

        expectComposeError(
            "invalid runtime volume name",
            matching: { if case .invalidVolumeName = $0 { true } else { false } },
            body: {
                _ = try VolumePlanning.runtimeVolumeName(projectName: "demo", volumeName: "bad/name")
            }
        )
    }

    private mutating func runNamedVolumePlanningTests() throws {
        let fixture = try ComposeParser.parse(fileURL: Self.fixtureURL("named-volumes-compose.yml"))
        let plans = try VolumePlanning.plans(
            composeFile: fixture,
            projectName: "demo",
            activeServiceNames: ["client", "server"]
        )
        expect(plans.count == 1, "one shared volume plan")
        expect(plans.first?.logicalName == "mydata", "plan logical name")
        expect(plans.first?.runtimeName == "demo_mydata", "plan runtime name")

        let undefined = try ComposeParser.parse(fileURL: Self.fixtureURL("volumes-undefined-compose.yml"))
        expectComposeError(
            "undefined volume reference",
            matching: { if case .undefinedVolume = $0 { true } else { false } },
            body: {
                try VolumePlanning.validate(
                    composeFile: undefined,
                    activeServiceNames: ["api"]
                )
            }
        )
    }

    private mutating func runNamedVolumePlannerArgumentTests() throws {
        let fixtureURL = Self.fixtureURL("named-volumes-compose.yml")
        let fixture = try ComposeParser.parse(fileURL: fixtureURL)
        let layers = try ServicePlanner.startupLayers(
            for: fixture,
            projectName: "demo",
            composeDirectory: fixtureURL.deletingLastPathComponent()
        )
        let plans = layers.flatMap { $0 }
        expect(plans.count == 2, "volumes fixture plan count")
        for plan in plans {
            guard let flagIndex = plan.runArguments.firstIndex(of: "-v") else {
                expect(false, "plan \(plan.name) emits -v flag")
                continue
            }
            let mount = plan.runArguments[plan.runArguments.index(after: flagIndex)]
            expect(mount.hasPrefix("demo_mydata:"), "plan \(plan.name) mounts demo_mydata")
            _ = try Application.ContainerRun.parse(plan.runArguments)
        }

        let readOnlyMount = try ServicePlanner.volumeFlag(
            for: "mydata:/app/data:ro",
            relativeTo: fixtureURL.deletingLastPathComponent(),
            projectName: "demo"
        )
        expect(readOnlyMount == "demo_mydata:/app/data:ro", "named volume mount preserves :ro")

        let undefinedURL = Self.fixtureURL("volumes-undefined-compose.yml")
        let undefined = try ComposeParser.parse(fileURL: undefinedURL)
        expectComposeError(
            "planner rejects undefined volume",
            matching: { if case .undefinedVolume = $0 { true } else { false } },
            body: {
                _ = try ServicePlanner.startupLayers(
                    for: undefined,
                    projectName: "demo",
                    composeDirectory: undefinedURL.deletingLastPathComponent()
                )
            }
        )
    }

    private mutating func runNamedVolumeMergeTests() throws {
        let mergeDirectory = Self.fixtureURL("merge/base-named-volumes.yml").deletingLastPathComponent()
        let merged = try ComposeParser.parse(fileURLs: [
            mergeDirectory.appendingPathComponent("base-named-volumes.yml"),
            mergeDirectory.appendingPathComponent("override-named-volumes.yml")
        ])
        expect(merged.volumes.keys.sorted() == ["cache", "data"], "merge unions root volumes")
        expect(
            Set(merged.services["web"]?.volumes ?? []) == ["data:/mnt/data", "cache:/mnt/cache"],
            "merge unions service volume mounts"
        )
    }

    private mutating func runNamedVolumeConfigTests() throws {
        let yaml = try ComposeConfigResolver.resolveOutput(
            fileURLs: [Self.fixtureURL("named-volumes-compose.yml")],
            activeProfiles: [],
            scaleOverrides: [:]
        )
        guard let yaml else {
            expect(false, "config export returned yaml for volumes fixture")
            return
        }
        expect(yaml.contains("volumes:"), "config yaml includes volumes block")
        expect(yaml.contains("mydata"), "config yaml includes volume name")
    }

    private mutating func runNamedVolumeLabelTests() {
        let labels = ComposeLabels.volumeLabels(projectName: "demo", logicalName: "mydata")
        expect(
            labels == [
                "com.docker.compose.project": "demo",
                "com.docker.compose.volume": "mydata"
            ],
            "volume create labels"
        )
    }
}
