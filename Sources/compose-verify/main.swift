import ComposeCore
import ContainerCommands
import ContainerizationError
import Foundation

struct TestRunner {
    var failures = 0

    mutating func expect(_ condition: @autoclosure () -> Bool, _ message: String, file: String = #file, line: Int = #line) {
        if !condition() {
            fputs("FAIL \(file):\(line): \(message)\n", stderr)
            failures += 1
        }
    }

    mutating func expectThrows<T: Error>(_ type: T.Type, _ message: String, _ body: () throws -> Void) {
        do {
            try body()
            fputs("FAIL: expected throw for \(message)\n", stderr)
            failures += 1
        } catch {
            guard error is T else {
                fputs("FAIL: wrong error type for \(message): \(error)\n", stderr)
                failures += 1
                return
            }
        }
    }

    mutating func expectComposeError(
        _ message: String,
        matching predicate: (ComposeError) -> Bool,
        _ body: () throws -> Void
    ) {
        do {
            try body()
            fputs("FAIL: expected throw for \(message)\n", stderr)
            failures += 1
        } catch let error as ComposeError {
            guard predicate(error) else {
                fputs("FAIL: wrong ComposeError case for \(message): \(error)\n", stderr)
                failures += 1
                return
            }
        } catch {
            fputs("FAIL: wrong error type for \(message): \(error)\n", stderr)
            failures += 1
        }
    }

    static func fixtureURL(_ name: String) -> URL {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return repoRoot.appendingPathComponent("Tests/composeTests/Fixtures/\(name)")
    }

    mutating func runParserTests() throws {
        let minimal = try ComposeParser.parse(fileURL: Self.fixtureURL("minimal-compose.yml"))
        expect(minimal.services.count == 1, "minimal service count")
        let web = minimal.services["web"]
        expect(web?.image == "docker.io/library/alpine:latest", "minimal image")
        expect(web?.command == .string("sleep 300"), "minimal command")
        expect(web?.ports == ["18080:80"], "minimal ports")

        let full = try ComposeParser.parse(fileURL: Self.fixtureURL("full-compose.yml"))
        expect(full.name == "demo", "full project name")
        expect(full.services.count == 2, "full service count")
        expect(full.services["api"]?.command == .list(["sleep", "600"]), "api command list")
        expect(full.services["api"]?.environment == .map(["FOO": "bar"]), "api environment map")
        expect(full.services["worker"]?.environment == .list(["BAZ=qux"]), "worker environment list")
        expect(full.services["worker"]?.containerName == "custom-worker", "worker container name")

        let missingImageURL = Self.fixtureURL("missing-image-compose.yml")
        expectThrows(ComposeError.self, "missing image") {
            _ = try ComposeParser.parse(fileURL: missingImageURL)
        }
        expectThrows(ComposeError.self, "missing file") {
            _ = try ComposeParser.parse(fileURL: URL(fileURLWithPath: "/tmp/does-not-exist-compose.yml"))
        }

        let volumesFixture = try ComposeParser.parse(fileURL: Self.fixtureURL("volumes-compose.yml"))
        expect(volumesFixture.services["web"]?.volumes == ["./data:/mnt/data"], "volumes fixture decode")
    }

    mutating func runPlannerTests() throws {
        let fixturesDirectory = Self.fixtureURL("minimal-compose.yml").deletingLastPathComponent()

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

        let publishFlag = try ServicePlanner.publishFlag(for: "8080:80/tcp")
        expect(publishFlag == "127.0.0.1:8080:80/tcp", "planner protocol suffix")
        expectThrows(ComposeError.self, "invalid port") {
            _ = try ServicePlanner.publishFlag(for: "not-a-port")
        }

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

        expectComposeError("invalid volume syntax", matching: { if case .unsupportedVolume = $0 { true } else { false } }) {
            _ = try ServicePlanner.volumeFlag(for: "foo", relativeTo: fixturesDirectory)
        }
        expectComposeError("named volume", matching: { if case .unsupportedNamedVolume = $0 { true } else { false } }) {
            _ = try ServicePlanner.volumeFlag(for: "mydata:/app", relativeTo: fixturesDirectory)
        }
        expectComposeError("volume option suffix", matching: { if case .unsupportedVolumeOption = $0 { true } else { false } }) {
            _ = try ServicePlanner.volumeFlag(for: "./data:/app:ro", relativeTo: fixturesDirectory)
        }
        expectComposeError("missing host path", matching: { if case .volumeHostPathNotFound = $0 { true } else { false } }) {
            _ = try ServicePlanner.volumeFlag(for: "./missing-dir:/mnt", relativeTo: fixturesDirectory)
        }
    }

    mutating func runLabelTests() {
        let flags = ComposeLabels.runFlags(projectName: "demo", serviceName: "web")
        expect(flags == ["-l", "com.docker.compose.project=demo", "-l", "com.docker.compose.service=web"], "run label flags")
    }

    mutating func runDependencyTests() throws {
        let fixturesDirectory = Self.fixtureURL("depends-compose.yml").deletingLastPathComponent()

        let dependsFixture = try ComposeParser.parse(fileURL: Self.fixtureURL("depends-compose.yml"))
        expect(dependsFixture.services["web"]?.dependsOn == ["db", "cache"], "depends_on decode")
        expect(dependsFixture.services["api"]?.dependsOn == ["db"], "depends_on single dep decode")
        expect(dependsFixture.services["db"]?.dependsOn == [], "depends_on default empty")

        let layers = try ServicePlanner.startupLayers(
            for: dependsFixture,
            projectName: "demo",
            composeDirectory: fixturesDirectory
        )
        expect(layers.count == 2, "depends layers wave count")
        expect(
            Set(layers[0].map(\.serviceName)) == ["cache", "db"],
            "depends layer 0 independent services"
        )
        expect(
            Set(layers[1].map(\.serviceName)) == ["api", "web"],
            "depends layer 1 dependents"
        )

        let flattened = layers.flatMap { $0 }
        let dbIndex = flattened.firstIndex { $0.serviceName == "db" }
        let webIndex = flattened.firstIndex { $0.serviceName == "web" }
        expect(dbIndex != nil && webIndex != nil, "depends flattened contains db and web")
        if let dbIndex, let webIndex {
            expect(dbIndex < webIndex, "depends db before web")
        }

        expectComposeError("unknown dependency", matching: { if case .unknownDependency = $0 { true } else { false } }) {
            _ = try ComposeParser.parse(fileURL: Self.fixtureURL("unknown-dependency-compose.yml"))
        }

        expectComposeError("circular dependency", matching: { if case .circularDependency = $0 { true } else { false } }) {
            _ = try ComposeParser.parse(fileURL: Self.fixtureURL("circular-dependency-compose.yml"))
        }

        expectComposeError("self dependency", matching: { if case .circularDependency = $0 { true } else { false } }) {
            _ = try ComposeParser.parse(fileURL: Self.fixtureURL("self-dependency-compose.yml"))
        }

        let duplicateDependsFixture = try ComposeParser.parse(fileURL: Self.fixtureURL("duplicate-depends-compose.yml"))
        let duplicateLayers = try ServicePlanner.startupLayers(
            for: duplicateDependsFixture,
            projectName: "demo",
            composeDirectory: fixturesDirectory
        )
        expect(duplicateLayers.count == 2, "duplicate depends_on layers wave count")
        expect(duplicateLayers[1].map(\.serviceName) == ["web"], "duplicate depends_on single dependent wave")

        expectComposeError("longform depends_on", matching: { if case .invalidField("depends_on", _) = $0 { true } else { false } }) {
            _ = try ComposeParser.parse(fileURL: Self.fixtureURL("longform-depends-compose.yml"))
        }
    }

    mutating func runShutdownLayerTests() throws {
        let dependsFixture = try ComposeParser.parse(fileURL: Self.fixtureURL("depends-compose.yml"))

        let serviceNames = ["api", "cache", "db", "web"]
        let allContainers = serviceNames.map { service in
            DiscoveredContainer(name: "demo_" + service, serviceName: service)
        }
        let allLayers = try ServicePlanner.shutdownContainerLayers(
            for: dependsFixture,
            containers: allContainers
        )
        expect(allLayers.count == 2, "shutdown layers wave count")
        expect(allLayers[0].map(\.serviceName) == ["api", "web"], "shutdown layer 0 dependents")
        expect(allLayers[1].map(\.serviceName) == ["cache", "db"], "shutdown layer 1 dependencies")

        let subsetContainers = [
            DiscoveredContainer(name: "demo_web", serviceName: "web"),
            DiscoveredContainer(name: "demo_db", serviceName: "db"),
        ]
        let subsetLayers = try ServicePlanner.shutdownContainerLayers(
            for: dependsFixture,
            containers: subsetContainers
        )
        expect(subsetLayers.count == 2, "shutdown subset wave count")
        expect(subsetLayers[0].map(\.serviceName) == ["web"], "shutdown subset layer 0")
        expect(subsetLayers[1].map(\.serviceName) == ["db"], "shutdown subset layer 1")

        let containers = [
            DiscoveredContainer(name: "demo_web", serviceName: "web"),
            DiscoveredContainer(name: "demo_db", serviceName: "db"),
            DiscoveredContainer(name: "legacy", serviceName: nil),
        ]
        let containerLayers = try ServicePlanner.shutdownContainerLayers(
            for: dependsFixture,
            containers: containers
        )
        expect(containerLayers.count == 3, "shutdown container layers include orphan wave")
        expect(containerLayers[0].map(\.name) == ["demo_web"], "shutdown container layer 0")
        expect(containerLayers[1].map(\.name) == ["demo_db"], "shutdown container layer 1")
        expect(containerLayers[2].map(\.name) == ["legacy"], "shutdown orphan final wave")

        expectComposeError("invalid compose file", matching: { if case .parseFailed = $0 { true } else { false } }) {
            _ = try ComposeParser.parse(fileURL: Self.fixtureURL("invalid-compose.yml"))
        }
    }

    mutating func runRollbackTests() {
        let rollbackResult = blockingAwait {
            let recorder = TearDownRecorder()
            let failures = await ServiceRunner.rollbackStartedContainers([["demo_db", "demo_web"]]) { name in
                await recorder.record(name)
            }
            let tornDown = await recorder.names
            return (failures, tornDown)
        }
        expect(rollbackResult.0.isEmpty, "rollback no failures")
        expect(
            Set(rollbackResult.1) == ["demo_db", "demo_web"],
            "rollback tears down all started containers"
        )

        enum TestError: Error { case boom }
        let rollbackFailures = blockingAwait {
            await ServiceRunner.rollbackStartedContainers([["bad"]]) { _ in
                throw TestError.boom
            }
        }
        expect(rollbackFailures.count == 1, "rollback records teardown failures")
        if rollbackFailures.count == 1 {
            expect(rollbackFailures[0].container == "bad", "rollback failure container name")
        }
    }

    mutating func runTeardownErrorTests() {
        let notFound = ContainerizationError(.notFound, message: "container with ID demo_web not found")
        expect(ContainerTeardown.isIgnorableError(notFound), "notFound is ignorable")

        let wrappedNotFound = ContainerizationError(
            .internalError,
            message: "failed to stop container",
            cause: notFound
        )
        expect(ContainerTeardown.isIgnorableError(wrappedNotFound), "wrapped notFound is ignorable")

        let invalidState = ContainerizationError(.invalidState, message: "container is running")
        expect(!ContainerTeardown.isIgnorableError(invalidState), "invalidState is not ignorable")

        let mixedAggregate = AggregateError([
            notFound,
            invalidState,
        ])
        expect(!ContainerTeardown.isIgnorableError(mixedAggregate), "mixed aggregate is not ignorable")

        let allNotFoundAggregate = AggregateError([
            notFound,
            ContainerizationError(.notFound, message: "other missing"),
        ])
        expect(ContainerTeardown.isIgnorableError(allNotFoundAggregate), "all-notFound aggregate is ignorable")

        expect(!ContainerTeardown.isIgnorableError(AggregateError([])), "empty aggregate is not ignorable")
    }
}

private actor TearDownRecorder {
    private(set) var names: [String] = []

    func record(_ name: String) {
        names.append(name)
    }
}

func blockingAwait<T>(_ body: @escaping @Sendable () async -> T) -> T {
    let semaphore = DispatchSemaphore(value: 0)
    let resultBox = BlockingResultBox<T>()
    Task {
        resultBox.value = await body()
        semaphore.signal()
    }
    semaphore.wait()
    return resultBox.value
}

private final class BlockingResultBox<T>: @unchecked Sendable {
    var value: T!
}

var runner = TestRunner()

do {
    try runner.runParserTests()
    try runner.runPlannerTests()
    try runner.runDependencyTests()
    try runner.runShutdownLayerTests()
    runner.runLabelTests()
    runner.runRollbackTests()
    runner.runTeardownErrorTests()
} catch {
    fputs("FAIL: unexpected error: \(error)\n", stderr)
    runner.failures += 1
}

if runner.failures > 0 {
    fputs("\(runner.failures) verification failure(s)\n", stderr)
    exit(1)
}

print("compose-verify: all checks passed")
