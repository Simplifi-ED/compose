import ComposeCore
import ContainerResource
import Foundation

extension TestRunner {
    mutating func runHealthcheckTests() throws {
        try runHealthcheckDecodeTests()
        try runHealthcheckValidationTests()
        try runHealthGateTests()
        runHealthWaitProbeTests()
        runHealthWaitStartedTests()
        runHealthWaitGateOrderTests()
        try runCompletedDependsTests()
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

        let replicaFixture = try ComposeParser.parse(fileURL: Self.fixtureURL("healthcheck-replicas-compose.yml"))
        let replicaContext = HealthWaitContext(services: replicaFixture.services, projectName: "demo")
        let replicaLayers = try ServicePlanner.startupLayers(
            for: replicaFixture,
            projectName: "demo",
            composeDirectory: fixturesDirectory
        )
        let replicaGates = try HealthWait.gatesForNextLayer(
            nextLayer: replicaLayers[1],
            context: replicaContext
        )
        expect(replicaGates[0].containerNames == ["demo_db_1", "demo_db_2"], "replica health gate names")
    }

    mutating func runHealthWaitProbeTests() {
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
                    runProcess: { _, _, _ in
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
                    runProcess: { _, _, _ in
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

    mutating func runHealthWaitStartedTests() {
        let statusCounter = StatusSequenceCounter(sequence: [.unknown, .running])
        let startedGate = HealthGate(
            dependencyService: "db",
            condition: .serviceStarted,
            containerNames: ["demo_db_1"]
        )
        let startedServices: [String: ComposeService] = [
            "db": ComposeService(
                image: "alpine",
                command: nil,
                ports: [],
                environment: nil,
                containerName: nil
            ),
            "web": ComposeService(
                image: "alpine",
                command: nil,
                ports: [],
                environment: nil,
                containerName: nil,
                dependsOn: [ComposeDependency(service: "db", condition: .serviceStarted)]
            )
        ]
        let startedOk = blockingAwait {
            do {
                try await HealthWait.waitForDependencies(
                    gates: [startedGate],
                    context: HealthWaitContext(services: startedServices, projectName: "demo"),
                    status: { id in
                        await statusCounter.next(for: id)
                    },
                    runProcess: { _, _, _ in 0 }
                )
                return true
            } catch {
                return false
            }
        }
        expect(startedOk, "service_started tolerates transient non-running status")
    }

    mutating func runHealthWaitGateOrderTests() {
        let services = Self.healthFixtureServices()
        let context = HealthWaitContext(services: services, projectName: "demo")
        let orderRecorder = GateOrderRecorder()
        let startedThenHealthy = [
            HealthGate(dependencyService: "db", condition: .serviceStarted, containerNames: ["demo_db_1"]),
            HealthGate(dependencyService: "db", condition: .serviceHealthy, containerNames: ["demo_db_1"]),
            HealthGate(
                dependencyService: "db",
                condition: .serviceCompletedSuccessfully,
                containerNames: ["demo_db_1"]
            )
        ]
        let orderedOk = blockingAwait {
            do {
                try await HealthWait.waitForDependencies(
                    gates: startedThenHealthy,
                    context: context,
                    status: { _ in .running },
                    runProcess: { _, _, _ in
                        await orderRecorder.recordProbe()
                        return 0
                    },
                    waitForExit: { _ in 0 },
                    onGate: { gate in
                        await orderRecorder.recordGate(gate.condition)
                    }
                )
                return true
            } catch {
                return false
            }
        }
        let gateOrder = blockingAwait { await orderRecorder.gateOrderSnapshot() }
        let probeCount = blockingAwait { await orderRecorder.probeCount() }
        expect(orderedOk, "parallel gate conditions complete")
        expect(
            gateOrder == [.serviceStarted, .serviceHealthy, .serviceCompletedSuccessfully],
            "readiness gates run in sort order"
        )
        expect(probeCount == 1, "healthy probe runs once after started gate")
    }

    static func healthFixtureServices(retries: Int = 2) -> [String: ComposeService] {
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

private actor StatusSequenceCounter {
    private var sequence: [RuntimeStatus?]

    init(sequence: [RuntimeStatus?]) {
        self.sequence = sequence
    }

    func next(for id: String) -> RuntimeStatus? {
        if sequence.isEmpty {
            return .running
        }
        if sequence.count == 1 {
            return sequence[0]
        }
        return sequence.removeFirst()
    }
}

private actor GateOrderRecorder {
    private var gateOrder: [DependsOnCondition] = []
    private var probes = 0

    func recordGate(_ condition: DependsOnCondition) {
        gateOrder.append(condition)
    }

    func recordProbe() {
        probes += 1
    }

    func gateOrderSnapshot() -> [DependsOnCondition] {
        gateOrder
    }

    func probeCount() -> Int {
        probes
    }
}

extension HealthWait {
    fileprivate static func waitForDependencies(
        gates: [HealthGate],
        context: HealthWaitContext,
        status: @escaping StatusProvider,
        runProcess: @escaping ProcessRunner,
        waitForExit: @escaping ExitCodeProvider = { _ in 0 },
        onGate: @escaping @Sendable (HealthGate) async -> Void
    ) async throws {
        let gatesByService = Dictionary(grouping: gates, by: \.dependencyService)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for serviceGates in gatesByService.values {
                group.addTask {
                    let ordered = serviceGates.sorted {
                        $0.condition.readinessSortOrder < $1.condition.readinessSortOrder
                    }
                    for gate in ordered {
                        await onGate(gate)
                        try await waitForDependencies(
                            gates: [gate],
                            context: context,
                            status: status,
                            runProcess: runProcess,
                            waitForExit: waitForExit
                        )
                    }
                }
            }
            try await group.waitForAll()
        }
    }
}
