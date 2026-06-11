import ComposeCore
import ContainerResource
import Foundation

extension TestRunner {
    mutating func runHealthcheckTests() throws {
        try runHealthcheckDecodeTests()
        try runHealthcheckValidationTests()
        try runHealthGateTests()
        runHealthWaitTests()
        runHealthOrchestrationTests()
    }

    mutating func runHealthcheckDecodeTests() throws {
        let fixture = try ComposeParser.parse(fileURL: Self.fixtureURL("healthcheck-compose.yml"))
        let dbHealth = fixture.services["db"]?.healthcheck
        expect(dbHealth != nil, "healthcheck decode present")
        expect(dbHealth?.retries == 2, "healthcheck retries decode")
        expect(dbHealth?.interval == .seconds(1), "healthcheck interval decode")

        let startedFixture = try ComposeParser.parse(fileURL: Self.fixtureURL("depends-started-compose.yml"))
        let startedDependency = startedFixture.services["web"]?.dependsOn.first
        expect(startedDependency?.condition == .serviceStarted, "service_started decode")
    }

    mutating func runHealthcheckValidationTests() throws {
        expectComposeError(
            "service_healthy without healthcheck",
            matching: { if case .invalidField("depends_on", _) = $0 { true } else { false } },
            body: {
                _ = try ComposeParser.parse(fileURL: Self.fixtureURL("healthcheck-missing-compose.yml"))
            }
        )

        expectComposeError(
            "unknown depends_on condition",
            matching: { if case .invalidField("depends_on", _) = $0 { true } else { false } },
            body: {
                _ = try ComposeParser.parse(fileURL: Self.fixtureURL("unknown-condition-compose.yml"))
            }
        )
    }

    mutating func runHealthGateTests() throws {
        let fixture = try ComposeParser.parse(fileURL: Self.fixtureURL("healthcheck-compose.yml"))
        let fixturesDirectory = Self.fixtureURL("healthcheck-compose.yml").deletingLastPathComponent()
        let layers = try ServicePlanner.startupLayers(
            for: fixture,
            projectName: "demo",
            composeDirectory: fixturesDirectory
        )
        expect(layers.count == 2, "healthcheck preserves dependency waves")

        let context = HealthWaitContext(services: fixture.services, projectName: "demo")
        let gates = try HealthWait.gatesForNextLayer(nextLayer: layers[1], context: context)
        expect(gates.count == 1, "health gate count")
        expect(gates[0].dependencyService == "db", "health gate dependency")
        expect(gates[0].condition == .serviceHealthy, "health gate condition")
        expect(gates[0].containerNames == ["demo_db_1"], "health gate container names")
    }

    mutating func runHealthWaitTests() {
        let services = Self.healthFixtureServices()
        let context = HealthWaitContext(services: services, projectName: "demo")
        let gate = HealthGate(
            dependencyService: "db",
            condition: .serviceHealthy,
            containerNames: ["demo_db_1"]
        )

        let probe = HealthProbeCounter(exitCodes: [1, 0])
        let waitSucceeded = blockingAwait {
            do {
                try await HealthWait.waitForDependencies(
                    gates: [gate],
                    context: context,
                    status: { _ in .running },
                    runProcess: { _, _ in
                        await probe.nextExitCode()
                    }
                )
                return true
            } catch {
                return false
            }
        }
        let attempts = blockingAwait { await probe.attemptCount() }
        expect(waitSucceeded, "health wait succeeds after retry")
        expect(attempts == 2, "health wait retries until success")

        let failingProbe = HealthProbeCounter(exitCodes: [1, 1, 1])
        let failed = blockingAwait {
            do {
                try await HealthWait.waitForDependencies(
                    gates: [gate],
                    context: context,
                    status: { _ in .running },
                    runProcess: { _, _ in
                        await failingProbe.nextExitCode()
                    }
                )
                return false
            } catch ComposeError.healthCheckTimeout {
                return true
            } catch {
                return false
            }
        }
        expect(failed, "health wait times out after retries")
    }

    mutating func runHealthOrchestrationTests() {
        let dbPlan = ServicePlan(serviceName: "db", name: "demo_db_1", runArguments: [])
        let webPlan = ServicePlan(serviceName: "web", name: "demo_web_1", runArguments: [])
        let services = Self.healthFixtureServices(retries: 1)
        let context = HealthWaitContext(services: services, projectName: "demo")
        let recorder = HealthOrchestrationRecorder()

        let success = blockingAwait {
            do {
                try await ServiceRunner.up(
                    layers: [[dbPlan], [webPlan]],
                    healthContext: context,
                    runContainer: { plan in
                        await recorder.recordStarted(plan.name)
                    },
                    rollbackTeardown: { name in
                        await recorder.recordRollback(name)
                    },
                    waitForDependencies: { gates, waitContext in
                        await recorder.recordWait(gates: gates)
                        try await HealthWait.waitForDependencies(
                            gates: gates,
                            context: waitContext,
                            status: { _ in .running },
                            runProcess: { _, _ in 0 }
                        )
                    }
                )
                return true
            } catch {
                return false
            }
        }

        let started = blockingAwait { await recorder.startedSnapshot() }
        let waits = blockingAwait { await recorder.waitSnapshot() }
        expect(success, "health orchestration completes")
        expect(started == ["demo_db_1", "demo_web_1"], "health orchestration startup order")
        expect(waits.count == 1, "health wait runs between waves")
        expect(waits[0].first?.dependencyService == "db", "health wait targets dependency")
    }
    private static func healthFixtureServices(retries: Int = 2) -> [String: ComposeService] {
        let healthcheck = ComposeHealthcheck(
            test: .cmd(["true"]),
            interval: .milliseconds(1),
            timeout: .milliseconds(50),
            retries: retries,
            startPeriod: .zero
        )
        return [
            "db": ComposeService(
                image: "alpine",
                command: nil,
                ports: [],
                environment: nil,
                containerName: nil,
                healthcheck: healthcheck
            ),
            "web": ComposeService(
                image: "alpine",
                command: nil,
                ports: [],
                environment: nil,
                containerName: nil,
                dependsOn: [ComposeDependency(service: "db", condition: .serviceHealthy)]
            )
        ]
    }
}

private actor HealthProbeCounter {
    private var exitCodes: [Int32]
    private var attempts = 0

    init(exitCodes: [Int32]) {
        self.exitCodes = exitCodes
    }

    func nextExitCode() -> Int32 {
        attempts += 1
        if exitCodes.isEmpty {
            return 0
        }
        if exitCodes.count == 1 {
            return exitCodes[0]
        }
        return exitCodes.removeFirst()
    }

    func attemptCount() -> Int {
        attempts
    }
}

private actor HealthOrchestrationRecorder {
    private var started: [String] = []
    private var rollback: [String] = []
    private var waits: [[HealthGate]] = []

    func recordStarted(_ name: String) {
        started.append(name)
    }

    func recordRollback(_ name: String) {
        rollback.append(name)
    }

    func recordWait(gates: [HealthGate]) {
        waits.append(gates)
    }

    func startedSnapshot() -> [String] {
        started
    }

    func waitSnapshot() -> [[HealthGate]] {
        waits
    }
}
