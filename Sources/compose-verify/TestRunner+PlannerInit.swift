import ComposeCore
import ContainerCommands
import Foundation

extension TestRunner {
    private static let plannerInitImage = "docker.io/library/alpine:3.24"

    func plannerAlpineService(useInit: Bool? = nil) -> ComposeService {
        ComposeService(
            image: Self.plannerInitImage,
            command: .string("sleep 300"),
            ports: [],
            environment: nil,
            containerName: nil,
            useInit: useInit
        )
    }

    func makeInitUpPlan(fixturesDirectory: URL) throws -> ServicePlan {
        let service = plannerAlpineService(useInit: true)
        let composeFile = ComposeFile(name: nil, services: ["web": service])
        let context = ServicePlanner.PlanningContext(
            composeFile: composeFile,
            projectName: "demo",
            composeDirectory: fixturesDirectory
        )
        return try ServicePlanner.buildUpPlan(
            context: context,
            serviceName: "web",
            service: service,
            replicaIndex: 1
        )
    }

    mutating func runPlannerInitTests(fixturesDirectory: URL) throws {
        try runPlannerInitUpAndRunTests(fixturesDirectory: fixturesDirectory)
        try runPlannerInitDefaultTests(fixturesDirectory: fixturesDirectory)
        try runPlannerInitStagingTests()
        try runPlannerInitDecodeTests()
    }

    mutating func runPlannerInitUpAndRunTests(fixturesDirectory: URL) throws {
        let upPlan = try makeInitUpPlan(fixturesDirectory: fixturesDirectory)
        expect(upPlan.runArguments.contains("--init"), "planner up plan includes --init")
        let initIndex = upPlan.runArguments.firstIndex(of: "--init")
        let imageIndex = upPlan.runArguments.firstIndex(of: Self.plannerInitImage)
        if let initIndex, let imageIndex {
            expect(initIndex < imageIndex, "planner --init precedes image ref")
        } else {
            expect(false, "planner missing --init or image in run arguments")
        }
        _ = try Application.ContainerRun.parse(upPlan.runArguments)

        let service = plannerAlpineService(useInit: true)
        let composeFile = ComposeFile(name: nil, services: ["web": service])
        let context = ServicePlanner.PlanningContext(
            composeFile: composeFile,
            projectName: "demo",
            composeDirectory: fixturesDirectory
        )
        let runPlan = try ServicePlanner.runPlan(
            context: context,
            serviceName: "web",
            service: service,
            options: RunPlanOptions(
                removeContainer: false,
                commandOverride: nil,
                interactive: false,
                processTerminal: false,
                nameSuffix: "00000001"
            )
        )
        expect(runPlan.runArguments.contains("--init"), "planner run plan includes --init")
        _ = try Application.ContainerRun.parse(runPlan.runArguments)
    }

    mutating func runPlannerInitDefaultTests(fixturesDirectory: URL) throws {
        let composeFile = ComposeFile(name: nil, services: ["web": plannerAlpineService()])
        let context = ServicePlanner.PlanningContext(
            composeFile: composeFile,
            projectName: "demo",
            composeDirectory: fixturesDirectory
        )

        let disabledPlan = try ServicePlanner.buildUpPlan(
            context: context,
            serviceName: "web",
            service: plannerAlpineService(useInit: false),
            replicaIndex: 1
        )
        expect(!disabledPlan.runArguments.contains("--init"), "planner init false omits --init")
        _ = try Application.ContainerRun.parse(disabledPlan.runArguments)

        let defaultPlan = try ServicePlanner.buildUpPlan(
            context: context,
            serviceName: "web",
            service: plannerAlpineService(),
            replicaIndex: 1
        )
        expect(!defaultPlan.runArguments.contains("--init"), "planner default omits --init")
        _ = try Application.ContainerRun.parse(defaultPlan.runArguments)
    }

    mutating func runPlannerInitStagingTests() throws {
        let fixtureURL = Self.fixtureURL("init-file-mounts-compose.yml")
        let fixturesDirectory = fixtureURL.deletingLastPathComponent()
        let composeFile = try ComposeParser.parse(fileURL: fixtureURL)
        let layers = try ServicePlanner.startupLayers(
            for: composeFile,
            projectName: "init-staging-demo",
            composeDirectory: fixturesDirectory
        )
        guard let plan = layers.first?.first else {
            expect(false, "init staging test produced a plan")
            return
        }
        defer { ComposeFileStaging.removeProjectStaging(projectName: plan.projectName) }

        expect(plan.runArguments.contains("--init"), "init staging plan includes --init")
        let prepared = try ComposeFileStaging.preparedRunArguments(for: plan)
        _ = try Application.ContainerRun.parse(prepared)

        let initIndex = prepared.firstIndex(of: "--init")
        let volumeIndex = prepared.firstIndex(of: "-v")
        let imageIndex = prepared.firstIndex(of: plan.image)
        if let initIndex, let volumeIndex, let imageIndex {
            expect(initIndex < volumeIndex, "init staging --init precedes staged volume mounts")
            expect(volumeIndex < imageIndex, "init staging staged volumes precede image")
        } else {
            expect(false, "init staging missing --init, -v, or image in prepared arguments")
        }
    }

    mutating func runPlannerInitDecodeTests() throws {
        let parsed = try ComposeParser.parse(fileURL: Self.fixtureURL("init-compose.yml"))
        expect(parsed.services["web"]?.useInit == true, "planner fixture decodes init true")
        expectComposeError(
            "planner invalid init type",
            matching: { if case .invalidField("init", _) = $0 { true } else { false } },
            body: {
                _ = try ComposeParser.parse(fileURL: Self.fixtureURL("init-bad-compose.yml"))
            }
        )
    }
}
