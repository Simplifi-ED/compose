import ComposeCore
import ContainerCommands
import Foundation

extension TestRunner {
    private static let resourceLimitsImage = "docker.io/library/alpine:3.24"

    mutating func runResourceLimitsTests() throws {
        try runResourceLimitsDecodeTests()
        try runResourceLimitsPlanTests()
        try runResourceLimitsValidationTests()
        try runGPUReservationTests()
        try runResourceLimitsConfigTests()
        try runResourceLimitsDryRunTests()
    }

    private mutating func runResourceLimitsDecodeTests() throws {
        let fixture = try ComposeParser.parse(fileURL: Self.fixtureURL("resources-limits-compose.yml"))
        let limits = fixture.services["web"]?.deploy?.resources?.limits
        expect(limits?.cpus == "2", "resource limits decode cpus")
        expect(limits?.memory == "512M", "resource limits decode memory")
    }

    private mutating func runResourceLimitsPlanTests() throws {
        try runResourceLimitsSinglePlanTests()
        try runResourceLimitsReplicaPlanTests()
    }

    private mutating func runResourceLimitsSinglePlanTests() throws {
        let fixtureURL = Self.fixtureURL("resources-limits-compose.yml")
        let composeFile = try ComposeParser.parse(fileURL: fixtureURL)
        let composeDirectory = fixtureURL.deletingLastPathComponent()
        let plan = try ServicePlanner.buildUpPlan(
            context: ServicePlanner.PlanningContext(
                composeFile: composeFile,
                projectName: "demo",
                composeDirectory: composeDirectory
            ),
            serviceName: "web",
            service: composeFile.services["web"]!,
            replicaIndex: 1
        )
        expect(runArgumentValue(plan.runArguments, flag: "--cpus") == "2", "plan includes whole cpu count")
        expect(runArgumentValue(plan.runArguments, flag: "--memory") == "512M", "plan includes memory limit")
        _ = try Application.ContainerRun.parse(plan.runArguments)

        let memoryOnly = ComposeService(
            image: Self.resourceLimitsImage,
            command: .string("sleep 300"),
            ports: [],
            environment: .map([:]),
            containerName: nil,
            deploy: ComposeDeploy(
                replicas: nil,
                resources: ComposeDeployResources(
                    limits: ComposeResourceLimits(cpus: nil, memory: "256M")
                )
            )
        )
        let memoryPlan = try ServicePlanner.buildUpPlan(
            context: ServicePlanner.PlanningContext(
                composeFile: ComposeFile(name: nil, services: ["web": memoryOnly]),
                projectName: "demo",
                composeDirectory: composeDirectory
            ),
            serviceName: "web",
            service: memoryOnly,
            replicaIndex: 1
        )
        expect(runArgumentValue(memoryPlan.runArguments, flag: "--cpus") == nil, "memory-only plan omits --cpus")
        expect(
            runArgumentValue(memoryPlan.runArguments, flag: "--memory") == "256M",
            "memory-only plan includes --memory"
        )
        _ = try Application.ContainerRun.parse(memoryPlan.runArguments)
    }

    private mutating func runResourceLimitsReplicaPlanTests() throws {
        let composeDirectory = Self.fixtureURL("scale-compose.yml").deletingLastPathComponent()
        let scaleFixture = try ComposeParser.parse(fileURL: Self.fixtureURL("scale-compose.yml"))
        let layers = try ServicePlanner.startupLayers(
            for: scaleFixture,
            projectName: "demo",
            composeDirectory: composeDirectory
        )
        let webPlans = layers.flatMap(\.self).filter { $0.serviceName == "web" }
        expect(webPlans.count == 2, "scale fixture plans two web replicas")
        for plan in webPlans {
            expect(runArgumentValue(plan.runArguments, flag: "--cpus") == "2", "replica plan includes cpus")
            expect(runArgumentValue(plan.runArguments, flag: "--memory") == "512M", "replica plan includes memory")
            _ = try Application.ContainerRun.parse(plan.runArguments)
        }
    }

    private mutating func runResourceLimitsConfigTests() throws {
        let fixtureURL = Self.fixtureURL("resources-limits-compose.yml")
        let resolved = try ComposeConfigResolver.resolve(
            fileURLs: [fixtureURL],
            activeProfiles: [],
            scaleOverrides: [:]
        )
        let limits = resolved.services["web"]?.deploy?.resources?.limits
        expect(limits?.cpus == "2", "config resolve retains cpus")
        expect(limits?.memory == "512M", "config resolve retains memory")
    }

    private mutating func runResourceLimitsDryRunTests() throws {
        let fixtureURL = Self.fixtureURL("resources-limits-compose.yml")
        let composeFile = try ComposeParser.parse(fileURL: fixtureURL)
        let composeDirectory = fixtureURL.deletingLastPathComponent()
        let plan = try ServicePlanner.buildUpPlan(
            context: ServicePlanner.PlanningContext(
                composeFile: composeFile,
                projectName: "demo",
                composeDirectory: composeDirectory
            ),
            serviceName: "web",
            service: composeFile.services["web"]!,
            replicaIndex: 1
        )
        let line = DryRunManifestFormatting.formatCreate(plan)
        expect(line.contains("cpu=\"2\""), "dry-run create shows cpu")
        expect(line.contains("memory=\"512M\""), "dry-run create shows memory")
    }
}
