import ComposeCore
import ContainerCommands
import Foundation

extension TestRunner {
    mutating func runPlannerTests() throws {
        let fixturesDirectory = Self.fixtureURL("minimal-compose.yml").deletingLastPathComponent()
        try runPlannerContainerTests(fixturesDirectory: fixturesDirectory)
        try runPlannerRunPlanTests(fixturesDirectory: fixturesDirectory)
        try runPlannerRunPlanDefaultTests(fixturesDirectory: fixturesDirectory)
        try runPlannerPublishTests(fixturesDirectory: fixturesDirectory)
        try runPlannerVolumeTests(fixturesDirectory: fixturesDirectory)
        try runPlannerVolumeErrorTests(fixturesDirectory: fixturesDirectory)
    }

    mutating func runPlannerRunPlanTests(fixturesDirectory: URL) throws {
        let service = ComposeService(
            image: "docker.io/library/alpine:latest",
            command: .string("sleep 300"),
            ports: ["18080:80"],
            environment: .map(["FOO": "bar"]),
            containerName: nil
        )
        let ioFlags = InteractiveSession.IOFlags.resolve(
            explicitInteractive: true,
            explicitTTY: true,
            stdinIsTTY: false
        )
        let composeFile = ComposeFile(name: nil, services: ["web": service])
        let context = ServicePlanner.PlanningContext(
            composeFile: composeFile,
            projectName: "demo",
            composeDirectory: fixturesDirectory
        )
        let plan = try ServicePlanner.runPlan(
            context: context,
            serviceName: "web",
            service: service,
            options: RunPlanOptions(
                removeContainer: true,
                commandOverride: ["echo", "hi"],
                interactive: ioFlags.interactive,
                processTerminal: ioFlags.processTerminal,
                nameSuffix: "abcd1234"
            )
        )
        expect(plan.name == "demo_web_run_abcd1234", "run plan unique container name")
        expect(!plan.runArguments.contains("-d"), "run plan foreground")
        expect(plan.runArguments.contains("--rm"), "run plan --rm")
        expect(plan.runArguments.contains("-i"), "run plan interactive")
        expect(plan.runArguments.contains("-t"), "run plan tty")
        expect(plan.runArguments.contains("echo"), "run plan command override")
        expect(plan.runArguments.contains("hi"), "run plan command override args")
        expect(
            plan.runArguments.contains("\(ComposeLabels.project)=demo"),
            "run plan project label"
        )
        _ = try Application.ContainerRun.parse(plan.runArguments)
    }

    mutating func runPlannerRunPlanDefaultTests(fixturesDirectory: URL) throws {
        let service = ComposeService(
            image: "docker.io/library/alpine:latest",
            command: .string("sleep 300"),
            ports: [],
            environment: nil,
            containerName: nil
        )
        let composeFile = ComposeFile(name: nil, services: ["web": service])
        let context = ServicePlanner.PlanningContext(
            composeFile: composeFile,
            projectName: "demo",
            composeDirectory: fixturesDirectory
        )
        let plan = try ServicePlanner.runPlan(
            context: context,
            serviceName: "web",
            service: service,
            options: RunPlanOptions(
                removeContainer: false,
                commandOverride: nil,
                interactive: false,
                processTerminal: false,
                nameSuffix: "00000000"
            )
        )
        expect(!plan.runArguments.contains("--rm"), "run plan default keeps container")
        expect(!plan.runArguments.contains("-i"), "run plan default non-interactive")
        expect(!plan.runArguments.contains("-t"), "run plan default no tty")
        _ = try Application.ContainerRun.parse(plan.runArguments)
    }

    mutating func runPlannerContainerTests(fixturesDirectory: URL) throws {
        let service = ComposeService(
            image: "docker.io/library/alpine:latest",
            command: .string("sleep 300"),
            ports: ["18080:80"],
            environment: .map(["FOO": "bar"]),
            containerName: nil
        )
        let composeFile = ComposeFile(name: nil, services: ["web": service])
        let context = ServicePlanner.PlanningContext(
            composeFile: composeFile,
            projectName: "demo",
            composeDirectory: fixturesDirectory
        )
        let plan = try ServicePlanner.buildUpPlan(
            context: context,
            serviceName: "web",
            service: service,
            replicaIndex: 1
        )
        expect(plan.name == "demo_web_1", "planner container name")
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

        let indexedPlan = try ServicePlanner.buildUpPlan(
            context: context,
            serviceName: "web",
            service: service,
            replicaIndex: 2
        )
        expect(indexedPlan.name == "demo_web_2", "planner replica index in container name")
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
        let volumeComposeFile = ComposeFile(name: nil, services: ["web": volumeService])
        let volumeContext = ServicePlanner.PlanningContext(
            composeFile: volumeComposeFile,
            projectName: "demo",
            composeDirectory: fixturesDirectory
        )
        let volumePlan = try ServicePlanner.buildUpPlan(
            context: volumeContext,
            serviceName: "web",
            service: volumeService,
            replicaIndex: 1
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
            "volume rw suffix",
            matching: { if case .unsupportedVolumeOption = $0 { true } else { false } },
            body: {
                _ = try ServicePlanner.volumeFlag(for: "./data:/app:rw", relativeTo: fixturesDirectory)
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
