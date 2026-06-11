import ComposeCore
import ContainerCommands
import ContainerizationError
import Foundation

extension TestRunner {
    mutating func runShutdownLayerTests() throws {
        try runShutdownLayerOrderingTests()
        try runShutdownParseTests()
        try runShutdownMultiFileMergeTests()
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
        expect(allShutdown.count == 2, "shutdown layers wave count")
        expect(Set(allShutdown[0].map(\.serviceName)) == ["api", "web"], "shutdown layer 0 dependents")
        expect(Set(allShutdown[1].map(\.serviceName)) == ["cache", "db"], "shutdown layer 1 dependencies")

        let subsetContainers = [
            DiscoveredContainer(name: "demo_web", serviceName: "web"),
            DiscoveredContainer(name: "demo_db", serviceName: "db")
        ]
        let subsetShutdown = try ServicePlanner.shutdownContainerLayers(
            for: dependsFixture,
            containers: subsetContainers
        )
        expect(subsetShutdown.count == 2, "shutdown subset wave count")
        expect(subsetShutdown[0].map(\.serviceName) == ["web"], "shutdown subset layer 0")
        expect(subsetShutdown[1].map(\.serviceName) == ["db"], "shutdown subset layer 1")

        let containers = [
            DiscoveredContainer(name: "demo_web", serviceName: "web"),
            DiscoveredContainer(name: "demo_db", serviceName: "db"),
            DiscoveredContainer(name: "legacy", serviceName: nil)
        ]
        let containerShutdown = try ServicePlanner.shutdownContainerLayers(
            for: dependsFixture,
            containers: containers
        )
        expect(containerShutdown.count == 3, "shutdown container layers include orphan wave")
        expect(containerShutdown[0].map(\.name) == ["demo_web"], "shutdown container layer 0")
        expect(containerShutdown[1].map(\.name) == ["demo_db"], "shutdown container layer 1")
        expect(containerShutdown[2].map(\.name) == ["legacy"], "shutdown orphan final wave")
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

    mutating func runShutdownMultiFileMergeTests() throws {
        let mergeDirectory = Self.fixtureURL("merge/base.yml").deletingLastPathComponent()
        let baseURL = mergeDirectory.appendingPathComponent("base.yml")
        let overrideURL = mergeDirectory.appendingPathComponent("override.yml")

        let shutdownMerged = try ComposeParser.parseForShutdown(fileURLs: [baseURL, overrideURL])
        expect(
            shutdownMerged.services["web"]?.dependsOn.serviceNames == ["db", "cache"],
            "shutdown multi-file merge depends_on"
        )
        let shutdownLayers = try ServicePlanner.shutdownContainerLayers(
            for: shutdownMerged,
            containers: [
                DiscoveredContainer(name: "demo_web", serviceName: "web"),
                DiscoveredContainer(name: "demo_db", serviceName: "db"),
                DiscoveredContainer(name: "demo_cache", serviceName: "cache")
            ]
        )
        expect(shutdownLayers.count == 2, "shutdown multi-file layer count")
        expect(shutdownLayers[0].map(\.serviceName) == ["web"], "shutdown multi-file dependents first")
    }

    mutating func runRollbackTests() {
        let partialRemoval = blockingAwait {
            await ServiceRunner.downReportsPartialRemovalOnInterrupt()
        }
        expect(partialRemoval == ["demo_fast"], "down reports removals completed before interrupt")

        let interruptRollback = blockingAwait {
            await ServiceRunner.upSkipsRollbackOnCancellation()
        }
        expect(interruptRollback.started == ["demo_fast"], "interrupt preserves started wave-1 containers")
        expect(interruptRollback.rollback.isEmpty, "interrupt skips rollback teardown")

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
