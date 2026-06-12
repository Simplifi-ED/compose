import ComposeCore
import ContainerAPIClient
import ContainerResource
import Containerization
import ContainerizationOCI
import Foundation

extension TestRunner {
    mutating func runWatchRuntimeTests() throws {
        try runWatchSyncTests()
        try runWatchRestartTests()
        try runWatchConfigurationTests()
    }

    private mutating func runWatchSyncTests() throws {
        let fixturesDirectory = Self.fixtureURL("develop-watch-compose.yml").deletingLastPathComponent()
        let resolved = try watchSyncResolvedRule(fixturesDirectory: fixturesDirectory)
        let hostFile = fixturesDirectory.appendingPathComponent("html/index.html")
        let containers = watchSyncReplicaContainers()
        let snapshot = makeWatchRunningSnapshot(project: "demo", service: "web")
        let syncInput = WatchSyncInput(
            resolved: resolved,
            hostFile: hostFile,
            containers: containers,
            snapshot: snapshot,
            expectedHostPath: hostFile.path,
            expectedDestination: "/usr/share/nginx/html/index.html"
        )
        let (syncResult, captured) = StandardStreamCapture.captureStandardError {
            blockingAwait { await watchSyncRecorderSnapshot(syncInput) }
        }

        expect(syncResult != nil, "sync completes without error")
        if let syncResult {
            expect(syncResult.copyCount == 2, "sync copies to all running replicas")
            expect(Set(syncResult.containers) == Set(["demo_web_1", "demo_web_2"]), "sync targets each replica")
            expect(syncResult.pathChecksPassed, "sync copyIn paths match watch mapping")
        }
        expect(
            captured.contains("Syncing web → demo_web_1: index.html"),
            "sync progress logged for first replica"
        )
        expect(
            captured.contains("Syncing web → demo_web_2: index.html"),
            "sync progress logged for second replica"
        )
    }

    private mutating func runWatchRestartTests() throws {
        let plans = [
            ServicePlan(serviceName: "web", name: "demo_web_1", runArguments: [], replicaIndex: 1),
            ServicePlan(serviceName: "web", name: "demo_web_2", runArguments: [], replicaIndex: 2),
            ServicePlan(serviceName: "db", name: "demo_db_1", runArguments: [], replicaIndex: 1)
        ]
        let restarted = blockingAwait { () -> [String] in
            let recorder = WatchRestartTestRecorder()
            do {
                try await ServiceRunnerRestart.restartPlans(plans.filter { $0.serviceName == "web" }) { plan in
                    recorder.record(plan.name)
                }
            } catch {
                fputs("FAIL: restart test threw: \(error)\n", stderr)
            }
            return recorder.names
        }
        expect(restarted.sorted() == ["demo_web_1", "demo_web_2"], "restart only targeted service plans")
    }

    private mutating func runWatchConfigurationTests() throws {
        let fixturesDirectory = Self.fixtureURL("develop-watch-compose.yml").deletingLastPathComponent()
        let composeFile = try ComposeParser.parse(fileURL: Self.fixtureURL("develop-watch-compose.yml"))
        let running = ProjectContainer(
            name: "demo_web_1",
            serviceName: "web",
            status: .running,
            publishedPorts: []
        )

        let configuration = try WatchSession.buildConfiguration(
            context: WatchSession.BuildContext(
                composeFile: composeFile,
                projectName: "demo",
                composeDirectory: fixturesDirectory,
                activeProfiles: [],
                serviceFilter: nil,
                containers: [running]
            )
        )
        expect(configuration.services.count == 1, "configuration includes watched service")
        expect(configuration.services[0].rules.count == 1, "configuration carries resolved rules")

        expectComposeError(
            "stopped service rejected",
            matching: { if case .serviceNotRunning = $0 { true } else { false } },
            body: {
                _ = try WatchSession.buildConfiguration(
                    context: WatchSession.BuildContext(
                        composeFile: composeFile,
                        projectName: "demo",
                        composeDirectory: fixturesDirectory,
                        activeProfiles: [],
                        serviceFilter: nil,
                        containers: [
                            ProjectContainer(
                                name: "demo_web_1",
                                serviceName: "web",
                                status: .stopped,
                                publishedPorts: []
                            )
                        ]
                    )
                )
            }
        )
    }

    private func makeWatchRunningSnapshot(project: String, service: String) -> ContainerSnapshot {
        let image = ImageDescription(
            reference: "docker.io/library/alpine:latest",
            descriptor: Descriptor(
                mediaType: "application/vnd.oci.image.manifest.v1+json",
                digest: "sha256:" + String(repeating: "0", count: 64),
                size: 0
            )
        )
        let process = ProcessConfiguration(
            executable: "/bin/sh",
            arguments: [],
            environment: [],
            user: .raw(userString: "root")
        )
        var configuration = ContainerConfiguration(id: "demo_web_1", image: image, process: process)
        configuration.labels = [
            ComposeLabels.project: project,
            ComposeLabels.service: service
        ]
        return ContainerSnapshot(
            configuration: configuration,
            status: .running,
            networks: []
        )
    }
}

private func watchSyncResolvedRule(fixturesDirectory: URL) throws -> ResolvedWatchRule {
    let develop = try ComposeParser.parse(fileURL: TestRunner.fixtureURL("develop-watch-compose.yml"))
        .services["web"]?.develop
    return try WatchPathValidator.validateRules(
        serviceName: "web",
        develop: develop,
        composeDirectory: fixturesDirectory
    )[0]
}

private func watchSyncReplicaContainers() -> [ProjectContainer] {
    [
        ProjectContainer(name: "demo_web_1", serviceName: "web", status: .running, publishedPorts: []),
        ProjectContainer(name: "demo_web_2", serviceName: "web", status: .running, publishedPorts: [])
    ]
}

private struct WatchSyncInput: Sendable {
    let resolved: ResolvedWatchRule
    let hostFile: URL
    let containers: [ProjectContainer]
    let snapshot: ContainerSnapshot
    let expectedHostPath: String
    let expectedDestination: String
}

private func watchSyncRecorderSnapshot(_ input: WatchSyncInput) async -> WatchSyncTestRecorder.Snapshot? {
    let recorder = WatchSyncTestRecorder(
        expectedSource: input.expectedHostPath,
        expectedDestination: input.expectedDestination
    )
    do {
        try await ContainerFileSync.sync(
            resolved: input.resolved,
            hostPath: input.hostFile,
            containers: input.containers,
            projectName: "demo",
            copyIn: { container, source, destination, _, _ in
                recorder.record(container: container, source: source, destination: destination)
            },
            getContainer: { _ in input.snapshot }
        )
        return recorder.snapshot()
    } catch {
        fputs("FAIL: sync test threw: \(error)\n", stderr)
        return nil
    }
}

private final class WatchSyncTestRecorder: @unchecked Sendable {
    struct Snapshot: Sendable {
        let copyCount: Int
        let containers: [String]
        let pathChecksPassed: Bool
    }

    private let lock = NSLock()
    private let expectedSource: String
    private let expectedDestination: String
    private var containers: [String] = []
    private var pathChecksPassed = true

    init(expectedSource: String, expectedDestination: String) {
        self.expectedSource = expectedSource
        self.expectedDestination = expectedDestination
    }

    func record(container: String, source: String, destination: String) {
        lock.lock()
        defer { lock.unlock() }
        containers.append(container)
        if source != expectedSource || destination != expectedDestination {
            pathChecksPassed = false
        }
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(
            copyCount: containers.count,
            containers: containers,
            pathChecksPassed: pathChecksPassed
        )
    }
}

private final class WatchRestartTestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var names: [String] = []

    func record(_ name: String) {
        lock.lock()
        defer { lock.unlock() }
        names.append(name)
    }
}
