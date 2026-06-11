import ComposeCore
import ContainerCommands
import Foundation

extension TestRunner {
    mutating func runScaleTests() throws {
        try runScaleDecodeTests()
        try runScaleExpansionTests()
        try runScaleOverrideTests()
        try runScaleErrorTests()
        try runScaleContainerNameTests()
        try runScalePortTests()
        try runScaleMergeTests()
        try runScaleOptionsTests()
        runScaleSummaryTests()
    }

    private mutating func runScaleDecodeTests() throws {
        let fixture = try ComposeParser.parse(fileURL: Self.fixtureURL("scale-compose.yml"))
        expect(fixture.services["web"]?.deploy?.replicas == 2, "deploy.replicas decode")
        expect(fixture.services["db"]?.deploy == nil, "deploy default nil")

        expectComposeError(
            "deploy.replicas zero rejected at parse",
            matching: { if case .invalidField("deploy.replicas", _) = $0 { true } else { false } },
            body: {
                _ = try ComposeParser.parse(fileURL: Self.fixtureURL("scale-replicas-zero-compose.yml"))
            }
        )
    }

    private mutating func runScaleExpansionTests() throws {
        let fixturesDirectory = Self.fixtureURL("scale-compose.yml").deletingLastPathComponent()
        let fixture = try ComposeParser.parse(fileURL: Self.fixtureURL("scale-compose.yml"))

        let plans = try ServicePlanner.plans(
            for: fixture,
            projectName: "demo",
            composeDirectory: fixturesDirectory
        )
        let webPlans = plans.filter { $0.serviceName == "web" }
        expect(webPlans.map(\.name) == ["demo_web_1", "demo_web_2"], "replica expansion indexed names")
        expect(webPlans.map(\.replicaIndex) == [1, 2], "replica expansion indices")
        expect(
            plans.filter { $0.serviceName == "db" }.map(\.name) == ["demo_db_1"],
            "single replica still uses index suffix"
        )

        for plan in webPlans {
            expect(
                plan.runArguments.contains("\(ComposeLabels.service)=web"),
                "replicas share the service label"
            )
            _ = try Application.ContainerRun.parse(plan.runArguments)
        }
        expect(
            webPlans[0].runArguments.contains("\(ComposeLabels.containerNumber)=1"),
            "first replica container-number label"
        )
        expect(
            webPlans[1].runArguments.contains("\(ComposeLabels.containerNumber)=2"),
            "second replica container-number label"
        )

        let dependsFixture = try ComposeParser.parse(fileURL: Self.fixtureURL("depends-compose.yml"))
        let layers = try ServicePlanner.startupLayers(
            for: dependsFixture,
            projectName: "demo",
            composeDirectory: fixturesDirectory,
            scaleOverrides: ["web": 2]
        )
        expect(layers.count == 2, "scaled service keeps dependency wave count")
        expect(
            Set(layers[1].map(\.name)).isSuperset(of: ["demo_web_1", "demo_web_2"]),
            "replicas share their service's dependency wave"
        )
    }

    private mutating func runScaleOverrideTests() throws {
        let fixturesDirectory = Self.fixtureURL("scale-compose.yml").deletingLastPathComponent()
        let fixture = try ComposeParser.parse(fileURL: Self.fixtureURL("scale-compose.yml"))

        let scaledUp = try ServicePlanner.plans(
            for: fixture,
            projectName: "demo",
            composeDirectory: fixturesDirectory,
            scaleOverrides: ["web": 3]
        )
        expect(
            scaledUp.filter { $0.serviceName == "web" }.count == 3,
            "--scale overrides deploy.replicas upward"
        )

        let scaledDown = try ServicePlanner.plans(
            for: fixture,
            projectName: "demo",
            composeDirectory: fixturesDirectory,
            scaleOverrides: ["web": 1]
        )
        expect(
            scaledDown.filter { $0.serviceName == "web" }.map(\.name) == ["demo_web_1"],
            "--scale overrides deploy.replicas downward"
        )
    }

    private mutating func runScaleErrorTests() throws {
        let fixturesDirectory = Self.fixtureURL("scale-compose.yml").deletingLastPathComponent()
        let fixture = try ComposeParser.parse(fileURL: Self.fixtureURL("scale-compose.yml"))

        expectComposeError(
            "unknown --scale service",
            matching: { if case .undefinedService = $0 { true } else { false } },
            body: {
                _ = try ServicePlanner.plans(
                    for: fixture,
                    projectName: "demo",
                    composeDirectory: fixturesDirectory,
                    scaleOverrides: ["ghost": 2]
                )
            }
        )

        let profiled = try ComposeParser.parse(fileURL: Self.fixtureURL("profiles-compose.yml"))
        expectComposeError(
            "--scale on profile-excluded service",
            matching: { if case .scaleServiceRequiresProfile = $0 { true } else { false } },
            body: {
                _ = try ServicePlanner.plans(
                    for: profiled,
                    projectName: "demo",
                    composeDirectory: fixturesDirectory,
                    scaleOverrides: ["debugger": 2]
                )
            }
        )
        let profiledPlans = try ServicePlanner.plans(
            for: profiled,
            projectName: "demo",
            composeDirectory: fixturesDirectory,
            activeProfiles: ["debug"],
            scaleOverrides: ["debugger": 2]
        )
        expect(
            profiledPlans.filter { $0.serviceName == "debugger" }.count == 2,
            "--scale works once the profile is active"
        )
    }

    private mutating func runScaleContainerNameTests() throws {
        let fixturesDirectory = Self.fixtureURL("full-compose.yml").deletingLastPathComponent()
        let fixture = try ComposeParser.parse(fileURL: Self.fixtureURL("full-compose.yml"))
        expectComposeError(
            "container_name conflicts with indexed naming",
            matching: { if case .containerNameNotSupportedWithReplicas = $0 { true } else { false } },
            body: {
                _ = try ServicePlanner.plans(
                    for: fixture,
                    projectName: "demo",
                    composeDirectory: fixturesDirectory
                )
            }
        )
    }

    private mutating func runScalePortTests() throws {
        let fixturesDirectory = Self.fixtureURL("scale-ports-compose.yml").deletingLastPathComponent()
        let fixture = try ComposeParser.parse(fileURL: Self.fixtureURL("scale-ports-compose.yml"))

        expectComposeError(
            "static host port blocks scaling",
            matching: { if case .staticPortBlocksScaling = $0 { true } else { false } },
            body: {
                _ = try ServicePlanner.plans(
                    for: fixture,
                    projectName: "demo",
                    composeDirectory: fixturesDirectory
                )
            }
        )

        let singleReplica = try ServicePlanner.plans(
            for: fixture,
            projectName: "demo",
            composeDirectory: fixturesDirectory,
            scaleOverrides: ["web": 1]
        )
        expect(
            singleReplica[0].runArguments.contains("127.0.0.1:8080:80"),
            "static host port still binds at one replica"
        )

        let scaled = try ComposeParser.parse(fileURL: Self.fixtureURL("scale-compose.yml"))
        let scaledPlans = try ServicePlanner.plans(
            for: scaled,
            projectName: "demo",
            composeDirectory: fixturesDirectory
        )
        expect(
            scaledPlans.allSatisfy { !$0.runArguments.contains("-p") },
            "container-only ports skip host binding"
        )

        let containerOnly = try ServicePlanner.publishFlag(for: "80")
        expect(containerOnly == nil, "container-only port publish flag")
        let containerOnlyProtocol = try ServicePlanner.publishFlag(for: ":80/udp")
        expect(containerOnlyProtocol == nil, "container-only port with protocol")
        expectThrows(ComposeError.self, "invalid container-only port") {
            _ = try ServicePlanner.publishFlag(for: ":not-a-port")
        }
    }

    private mutating func runScaleMergeTests() throws {
        let merged = try ComposeParser.parse(fileURLs: [
            Self.fixtureURL("scale-merge/base.yml"),
            Self.fixtureURL("scale-merge/override.yml")
        ])
        expect(merged.services["web"]?.deploy?.replicas == 2, "override replicas replaces base")
    }

    private mutating func runScaleOptionsTests() throws {
        let options = try ScaleOptions.parse(["--scale", "web=3", "--scale", "db=2", "--scale", "web=4"])
        let overrides = try options.resolvedScaleOverrides()
        expect(overrides == ["web": 4, "db": 2], "repeated --scale entries parse; last wins per service")

        for invalid in ["web", "web=0", "web=-1", "web=abc", "=3"] {
            expectComposeError(
                "invalid --scale value '\(invalid)'",
                matching: { if case .invalidScaleSpec = $0 { true } else { false } },
                body: {
                    _ = try ScaleOptions.parse(["--scale", invalid]).resolvedScaleOverrides()
                }
            )
        }
    }

    private mutating func runScaleSummaryTests() {
        let plans = [
            ServicePlan(serviceName: "web", name: "demo_web_1", runArguments: [], replicaIndex: 1),
            ServicePlan(serviceName: "web", name: "demo_web_2", runArguments: [], replicaIndex: 2),
            ServicePlan(serviceName: "db", name: "demo_db_1", runArguments: [], replicaIndex: 1)
        ]
        expect(
            UpStartupSummary.lines(for: plans) == [
                "web  demo_web_1  demo_web_2",
                "db   demo_db_1"
            ],
            "up summary aligns service column and groups replicas"
        )
        expect(UpStartupSummary.lines(for: []).isEmpty, "up summary empty plans")
    }
}
