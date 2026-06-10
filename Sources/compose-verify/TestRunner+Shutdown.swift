import ComposeCore
import ContainerCommands
import ContainerizationError
import Foundation

extension TestRunner {
    mutating func runShutdownLayerTests() throws {
        try runShutdownLayerOrderingTests()
        try runShutdownParseTests()
    }

    mutating func runShutdownLayerOrderingTests() throws {
        let dependsFixture = try ComposeParser.parse(fileURL: Self.fixtureURL("depends-compose.yml"))

        let serviceNames = ["api", "cache", "db", "web"]
        let allContainers = serviceNames.map { service in
            DiscoveredContainer(name: "demo_" + service, serviceName: service)
        }
        let allShutdown = try ServicePlanner.shutdownContainerLayers(
            for: dependsFixture,
            containers: allContainers
        )
        expect(allShutdown.layers.count == 2, "shutdown layers wave count")
        expect(allShutdown.layers[0].map(\.serviceName) == ["api", "web"], "shutdown layer 0 dependents")
        expect(allShutdown.layers[1].map(\.serviceName) == ["cache", "db"], "shutdown layer 1 dependencies")

        let subsetContainers = [
            DiscoveredContainer(name: "demo_web", serviceName: "web"),
            DiscoveredContainer(name: "demo_db", serviceName: "db")
        ]
        let subsetShutdown = try ServicePlanner.shutdownContainerLayers(
            for: dependsFixture,
            containers: subsetContainers
        )
        expect(subsetShutdown.layers.count == 2, "shutdown subset wave count")
        expect(subsetShutdown.layers[0].map(\.serviceName) == ["web"], "shutdown subset layer 0")
        expect(subsetShutdown.layers[1].map(\.serviceName) == ["db"], "shutdown subset layer 1")

        let containers = [
            DiscoveredContainer(name: "demo_web", serviceName: "web"),
            DiscoveredContainer(name: "demo_db", serviceName: "db"),
            DiscoveredContainer(name: "legacy", serviceName: nil)
        ]
        let containerShutdown = try ServicePlanner.shutdownContainerLayers(
            for: dependsFixture,
            containers: containers
        )
        expect(containerShutdown.layers.count == 3, "shutdown container layers include orphan wave")
        expect(containerShutdown.layers[0].map(\.name) == ["demo_web"], "shutdown container layer 0")
        expect(containerShutdown.layers[1].map(\.name) == ["demo_db"], "shutdown container layer 1")
        expect(containerShutdown.layers[2].map(\.name) == ["legacy"], "shutdown orphan final wave")
        expect(containerShutdown.orphans.map(\.name) == ["legacy"], "shutdown orphan list")
    }

    mutating func runShutdownParseTests() throws {
        expectComposeError(
            "invalid compose file",
            matching: { if case .parseFailed = $0 { true } else { false } },
            body: {
                _ = try ComposeParser.parse(fileURL: Self.fixtureURL("invalid-compose.yml"))
            }
        )

        let shutdownParse = try ComposeParser.parseForShutdown(
            fileURL: Self.fixtureURL("missing-image-compose.yml")
        )
        expect(shutdownParse.services["web"] != nil, "parseForShutdown accepts missing image")
        expectComposeError(
            "full parse rejects missing image",
            matching: { if case .missingImage = $0 { true } else { false } },
            body: {
                _ = try ComposeParser.parse(fileURL: Self.fixtureURL("missing-image-compose.yml"))
            }
        )
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
            invalidState
        ])
        expect(!ContainerTeardown.isIgnorableError(mixedAggregate), "mixed aggregate is not ignorable")

        let allNotFoundAggregate = AggregateError([
            notFound,
            ContainerizationError(.notFound, message: "other missing")
        ])
        expect(ContainerTeardown.isIgnorableError(allNotFoundAggregate), "all-notFound aggregate is ignorable")

        expect(!ContainerTeardown.isIgnorableError(AggregateError([])), "empty aggregate is not ignorable")
    }
}
