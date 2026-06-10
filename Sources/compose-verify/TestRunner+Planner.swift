import ComposeCore
import ContainerCommands
import Foundation

extension TestRunner {
    mutating func runPlannerTests() throws {
        let fixturesDirectory = Self.fixtureURL("minimal-compose.yml").deletingLastPathComponent()
        try runPlannerContainerTests(fixturesDirectory: fixturesDirectory)
        try runPlannerPublishTests(fixturesDirectory: fixturesDirectory)
        try runPlannerVolumeTests(fixturesDirectory: fixturesDirectory)
        try runPlannerVolumeErrorTests(fixturesDirectory: fixturesDirectory)
    }

    mutating func runPlannerContainerTests(fixturesDirectory: URL) throws {
        let service = ComposeService(
            image: "docker.io/library/alpine:latest",
            command: .string("sleep 300"),
            ports: ["18080:80"],
            environment: .map(["FOO": "bar"]),
            containerName: nil
        )
        let plan = try ServicePlanner.plan(
            serviceName: "web",
            service: service,
            projectName: "demo",
            composeDirectory: fixturesDirectory
        )
        expect(plan.name == "demo_web", "planner container name")
        expect(plan.runArguments.contains("-d"), "planner detach")
        expect(plan.runArguments.contains("127.0.0.1:18080:80"), "planner publish")
        expect(plan.runArguments.contains("-l"), "planner label flag")
        expect(
            plan.runArguments.contains("\(ComposeLabels.project)=demo"),
            "planner project label"
        )
        expect(
            plan.runArguments.contains("\(ComposeLabels.service)=web"),
            "planner service label"
        )

        let named = ComposeService(
            image: "docker.io/library/alpine:latest",
            command: nil,
            ports: [],
            environment: nil,
            containerName: "custom-worker"
        )
        let namedPlan = try ServicePlanner.plan(
            serviceName: "worker",
            service: named,
            projectName: "demo",
            composeDirectory: fixturesDirectory
        )
        expect(namedPlan.name == "custom-worker", "planner container name override")
    }

    mutating func runPlannerPublishTests(fixturesDirectory: URL) throws {
        let publishFlag = try ServicePlanner.publishFlag(for: "8080:80/tcp")
        expect(publishFlag == "127.0.0.1:8080:80/tcp", "planner protocol suffix")
        expectThrows(ComposeError.self, "invalid port") {
            _ = try ServicePlanner.publishFlag(for: "not-a-port")
        }
    }

    mutating func runPlannerVolumeTests(fixturesDirectory: URL) throws {
        let absoluteVolume = try ServicePlanner.volumeFlag(for: "/tmp:/mnt/tmp", relativeTo: fixturesDirectory)
        expect(absoluteVolume == "/tmp:/mnt/tmp", "volume flag absolute host path")

        let relativeVolume = try ServicePlanner.volumeFlag(for: "./data:/mnt/data", relativeTo: fixturesDirectory)
        let expectedDataPath = fixturesDirectory.appendingPathComponent("data").standardizedFileURL.path
        expect(relativeVolume == "\(expectedDataPath):/mnt/data", "volume flag relative host path")

        let fileVolume = try ServicePlanner.volumeFlag(
            for: "./data/sample.txt:/mnt/sample.txt",
            relativeTo: fixturesDirectory
        )
        let expectedFilePath = fixturesDirectory.appendingPathComponent("data/sample.txt").standardizedFileURL.path
        expect(fileVolume == "\(expectedFilePath):/mnt/sample.txt", "volume flag file bind mount")

        let volumeService = ComposeService(
            image: "docker.io/library/alpine:latest",
            command: .string("sleep 300"),
            ports: [],
            volumes: ["./data:/mnt/data"],
            environment: nil,
            containerName: nil
        )
        let volumePlan = try ServicePlanner.plan(
            serviceName: "web",
            service: volumeService,
            projectName: "demo",
            composeDirectory: fixturesDirectory
        )
        expect(volumePlan.runArguments.contains("-v"), "planner volume flag")
        expect(volumePlan.runArguments.contains("\(expectedDataPath):/mnt/data"), "planner resolved volume")

        _ = try Application.ContainerRun.parse(volumePlan.runArguments)
    }

    mutating func runPlannerVolumeErrorTests(fixturesDirectory: URL) throws {
        expectComposeError(
            "invalid volume syntax",
            matching: { if case .unsupportedVolume = $0 { true } else { false } },
            body: {
                _ = try ServicePlanner.volumeFlag(for: "foo", relativeTo: fixturesDirectory)
            }
        )
        expectComposeError(
            "named volume",
            matching: { if case .unsupportedNamedVolume = $0 { true } else { false } },
            body: {
                _ = try ServicePlanner.volumeFlag(for: "mydata:/app", relativeTo: fixturesDirectory)
            }
        )
        expectComposeError(
            "volume option suffix",
            matching: { if case .unsupportedVolumeOption = $0 { true } else { false } },
            body: {
                _ = try ServicePlanner.volumeFlag(for: "./data:/app:ro", relativeTo: fixturesDirectory)
            }
        )
        expectComposeError(
            "missing host path",
            matching: { if case .volumeHostPathNotFound = $0 { true } else { false } },
            body: {
                _ = try ServicePlanner.volumeFlag(for: "./missing-dir:/mnt", relativeTo: fixturesDirectory)
            }
        )
    }
}
