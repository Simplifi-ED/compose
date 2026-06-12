import ComposeCore
import ContainerCommands
import Foundation

extension TestRunner {
    mutating func runNetworkTests() throws {
        try runNetworkParserTests()
        try runNetworkParserErrorTests()
        try runNetworkNameTests()
        try runNetworkPlanningTests()
        try runNetworkPlannerArgumentTests()
        try runNetworkMergeTests()
        try runNetworkConfigTests()
        try runNetworkNullOverrideTests()
        try runNetworkShutdownTests()
        runNetworkLabelTests()
    }

    private mutating func runNetworkParserTests() throws {
        let fixture = try ComposeParser.parse(fileURL: Self.fixtureURL("networks-compose.yml"))
        expect(fixture.networks.keys.sorted() == ["backend"], "root networks decode")
        expect(fixture.services["client"]?.networks == ["backend"], "service networks short list decode")
        expect(fixture.services["server"]?.networks == ["backend"], "service networks map form decode")
        let minimal = try ComposeParser.parse(fileURL: Self.fixtureURL("minimal-compose.yml"))
        expect(minimal.networks.isEmpty, "no networks block decodes to empty map")
    }

    private mutating func runNetworkParserErrorTests() throws {
        expectComposeError(
            "external network",
            matching: { if case .unsupportedExternalNetwork = $0 { true } else { false } },
            body: {
                _ = try ComposeParser.parse(fileURL: Self.fixtureURL("networks-external-compose.yml"))
            }
        )
        expectComposeError(
            "service network option",
            matching: { if case .unsupportedNetworkOption = $0 { true } else { false } },
            body: {
                _ = try ComposeParser.parse(fileURL: Self.fixtureURL("networks-option-compose.yml"))
            }
        )
        expectComposeError(
            "network_mode rejected",
            matching: { if case .invalidField("network_mode", _) = $0 { true } else { false } },
            body: {
                _ = try ComposeParser.parse(fileURL: Self.fixtureURL("networks-mode-compose.yml"))
            }
        )
    }

    private mutating func runNetworkNameTests() throws {
        let runtimeName = try NetworkPlanning.runtimeNetworkName(projectName: "demo", networkName: "backend")
        expect(runtimeName == "demo_backend", "runtime network name")

        expectComposeError(
            "invalid runtime network name",
            matching: { if case .invalidNetworkName = $0 { true } else { false } },
            body: {
                _ = try NetworkPlanning.runtimeNetworkName(projectName: "demo", networkName: "Bad-Name")
            }
        )
        expectComposeError(
            "overlong runtime network name",
            matching: { if case .invalidNetworkName = $0 { true } else { false } },
            body: {
                _ = try NetworkPlanning.runtimeNetworkName(
                    projectName: "demo",
                    networkName: String(repeating: "a", count: 64)
                )
            }
        )
    }

    private mutating func runNetworkPlanningTests() throws {
        let fixture = try ComposeParser.parse(fileURL: Self.fixtureURL("networks-compose.yml"))
        let plans = try NetworkPlanning.plans(
            composeFile: fixture,
            projectName: "demo",
            activeServiceNames: ["client", "server"]
        )
        expect(plans.count == 1, "one shared network plan")
        expect(plans.first?.logicalName == "backend", "plan logical name")
        expect(plans.first?.runtimeName == "demo_backend", "plan runtime name")

        let undefined = try ComposeParser.parse(fileURL: Self.fixtureURL("networks-undefined-compose.yml"))
        expectComposeError(
            "undefined network reference",
            matching: { if case .undefinedNetwork = $0 { true } else { false } },
            body: {
                try NetworkPlanning.validate(
                    composeFile: undefined,
                    activeServiceNames: ["api"]
                )
            }
        )

        let flags = try NetworkPlanning.networkFlags(
            service: fixture.services["client"]!,
            projectName: "demo"
        )
        expect(flags == ["--network", "demo_backend"], "network flags for member service")

        let detached = ComposeService(
            image: "docker.io/library/alpine:3.24",
            command: nil,
            ports: [],
            environment: nil,
            containerName: nil
        )
        let detachedFlags = try NetworkPlanning.networkFlags(service: detached, projectName: "demo")
        expect(detachedFlags.isEmpty, "no network flags when service omits networks")
    }

    private mutating func runNetworkPlannerArgumentTests() throws {
        let fixtureURL = Self.fixtureURL("networks-compose.yml")
        let fixture = try ComposeParser.parse(fileURL: fixtureURL)
        let layers = try ServicePlanner.startupLayers(
            for: fixture,
            projectName: "demo",
            composeDirectory: fixtureURL.deletingLastPathComponent()
        )
        let plans = layers.flatMap { $0 }
        expect(plans.count == 2, "networks fixture plan count")
        for plan in plans {
            guard let flagIndex = plan.runArguments.firstIndex(of: "--network") else {
                expect(false, "plan \(plan.name) emits --network flag")
                continue
            }
            expect(
                plan.runArguments[plan.runArguments.index(after: flagIndex)] == "demo_backend",
                "plan \(plan.name) attaches demo_backend"
            )
            _ = try Application.ContainerRun.parse(plan.runArguments)
        }

        let undefinedURL = Self.fixtureURL("networks-undefined-compose.yml")
        let undefined = try ComposeParser.parse(fileURL: undefinedURL)
        expectComposeError(
            "planner rejects undefined network",
            matching: { if case .undefinedNetwork = $0 { true } else { false } },
            body: {
                _ = try ServicePlanner.startupLayers(
                    for: undefined,
                    projectName: "demo",
                    composeDirectory: undefinedURL.deletingLastPathComponent()
                )
            }
        )
    }

    private mutating func runNetworkMergeTests() throws {
        let mergeDirectory = Self.fixtureURL("merge/base-networks.yml").deletingLastPathComponent()
        let merged = try ComposeParser.parse(fileURLs: [
            mergeDirectory.appendingPathComponent("base-networks.yml"),
            mergeDirectory.appendingPathComponent("override-networks.yml")
        ])
        expect(merged.networks.keys.sorted() == ["backend", "frontend"], "merge unions root networks")
        expect(
            merged.services["web"]?.networks == ["backend", "frontend"],
            "merge unions service network membership"
        )
    }

    private mutating func runNetworkConfigTests() throws {
        let yaml = try ComposeConfigResolver.resolveOutput(
            fileURLs: [Self.fixtureURL("networks-compose.yml")],
            activeProfiles: [],
            scaleOverrides: [:]
        )
        guard let yaml else {
            expect(false, "config export returned yaml for networks fixture")
            return
        }
        expect(yaml.contains("networks:"), "config yaml includes networks block")
        expect(yaml.contains("backend"), "config yaml includes network name")
    }

    private mutating func runNetworkNullOverrideTests() throws {
        let single = try ComposeParser.parse(
            fileURL: Self.fixtureURL("networks-null-override-compose.yml")
        )
        expect(single.services["api"]?.networks.isEmpty == true, "null service network decodes as disconnect")

        let mergeDirectory = Self.fixtureURL("merge/base-networks.yml").deletingLastPathComponent()
        let nullMerged = try ComposeParser.parse(fileURLs: [
            mergeDirectory.appendingPathComponent("base-networks.yml"),
            mergeDirectory.appendingPathComponent("override-network-null.yml")
        ])
        expect(
            nullMerged.services["web"]?.networks.isEmpty == true,
            "merge applies null network override disconnect"
        )
    }

    private mutating func runNetworkLabelTests() {
        let labels = ComposeLabels.networkLabels(projectName: "demo", logicalName: "backend")
        expect(
            labels == [
                "com.docker.compose.project": "demo",
                "com.docker.compose.network": "backend"
            ],
            "network create labels"
        )
    }
}
