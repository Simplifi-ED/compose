import ComposeCore
import ContainerAPIClient
import ContainerResource
import Containerization
import ContainerizationOCI
import Foundation

extension TestRunner {
    mutating func runWatchResilienceTests() throws {
        try runWatchScaleFromDiscoveryTests()
        try runWatchPreflightSyncTests()
        try runWatchPlansMatchingRunningTests()
    }

    private mutating func runWatchScaleFromDiscoveryTests() throws {
        let fixturesDirectory = Self.fixtureURL("develop-watch-compose.yml").deletingLastPathComponent()
        let composeFile = try ComposeParser.parse(fileURL: Self.fixtureURL("develop-watch-compose.yml"))
        let containers = (1...3).map { index in
            ProjectContainer(
                name: "demo_web_\(index)",
                serviceName: "web",
                status: .running,
                publishedPorts: []
            )
        }

        let configuration = try WatchSession.buildConfiguration(
            context: WatchSession.BuildContext(
                composeFile: composeFile,
                projectName: "demo",
                composeDirectory: fixturesDirectory,
                activeProfiles: [],
                serviceFilter: nil,
                containers: containers
            )
        )

        expect(configuration.services.count == 1, "discovery scale includes watched service")
        expect(configuration.services[0].plans.count == 3, "plans match running replica count from discovery")
        expect(
            Set(configuration.services[0].plans.map(\.name)) == Set(["demo_web_1", "demo_web_2", "demo_web_3"]),
            "plans name each discovered replica"
        )
    }

    private mutating func runWatchPreflightSyncTests() throws {
        let fixturesDirectory = Self.fixtureURL("develop-watch-compose.yml").deletingLastPathComponent()
        let rules = try WatchPathValidator.validateRules(
            serviceName: "web",
            develop: try ComposeParser.parse(fileURL: Self.fixtureURL("develop-watch-compose.yml"))
                .services["web"]?.develop,
            composeDirectory: fixturesDirectory
        )
        let resolved = rules[0]
        let hostFile = fixturesDirectory.appendingPathComponent("html/index.html")
        let containers = [
            ProjectContainer(name: "demo_web_1", serviceName: "web", status: .running, publishedPorts: []),
            ProjectContainer(name: "demo_web_2", serviceName: "web", status: .running, publishedPorts: [])
        ]
        let snapshot = watchResilienceSnapshot(project: "demo", service: "web")

        let copyCount = blockingAwait { () -> Int in
            let recorder = WatchPreflightTestRecorder()
            do {
                try await ContainerFileSync.sync(
                    resolved: resolved,
                    hostPath: hostFile,
                    containers: containers,
                    projectName: "demo",
                    copyIn: { _, _, _, _, _ in
                        recorder.recordCopy()
                    },
                    getContainer: { name in
                        if name == "demo_web_2" {
                            throw ComposeError.serviceNotRunning(service: "web", state: "missing")
                        }
                        return snapshot
                    }
                )
            } catch {
                return recorder.copyCount
            }
            return recorder.copyCount
        }

        expect(copyCount == 0, "preflight failure skips all copyIn calls")
    }

    private mutating func runWatchPlansMatchingRunningTests() throws {
        let snapshot = watchResilienceSnapshot(project: "demo", service: "web")
        let runtime = WatchServiceRuntime(
            serviceName: "web",
            plans: [
                ServicePlan(serviceName: "web", name: "demo_web_1", runArguments: [], replicaIndex: 1),
                ServicePlan(serviceName: "web", name: "demo_web_2", runArguments: [], replicaIndex: 2)
            ],
            containers: [
                ProjectContainer(name: "demo_web_1", serviceName: "web", status: .running, publishedPorts: []),
                ProjectContainer(name: "demo_web_3", serviceName: "web", status: .running, publishedPorts: [])
            ],
            listContainers: { [] },
            getContainer: { _ in snapshot }
        )

        let mismatch = blockingAwait {
            do {
                _ = try await runtime.plansMatchingRunning()
                return false
            } catch {
                return true
            }
        }
        expect(mismatch, "running/plan mismatch is rejected before restart")
    }
}

private func watchResilienceSnapshot(project: String, service: String) -> ContainerSnapshot {
    let image = ImageDescription(
        reference: "docker.io/library/alpine:3.24",
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

private final class WatchPreflightTestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var copyCount = 0

    func recordCopy() {
        lock.lock()
        defer { lock.unlock() }
        copyCount += 1
    }
}
