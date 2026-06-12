import ComposeCore
import ContainerResource
import Foundation

extension TestRunner {
    mutating func runCompletedDependsTests() throws {
        try runCompletedDependsDecodeTests()
        try runCompletedDependsGateTests()
        runCompletedDependsWaitSuccessTest()
        runCompletedDependsWaitFailureTest()
        runCompletedDependsFastExitTest()
        runCompletedDependsWaitTimeoutTest()
        runCompletedDependsExitWaitTimeoutTest()
        try runCompletedDependsMachinePlanRejectionTest()
        runCompletedDependsMachineRuntimeRejectionTest()
    }

    mutating func runCompletedDependsDecodeTests() throws {
        let fixture = try ComposeParser.parse(fileURL: Self.fixtureURL("depends-completed-compose.yml"))
        let dependency = fixture.services["app"]?.dependsOn.first
        expect(dependency?.condition == .serviceCompletedSuccessfully, "service_completed_successfully decode")
    }

    mutating func runCompletedDependsGateTests() throws {
        let fixture = try ComposeParser.parse(fileURL: Self.fixtureURL("depends-completed-compose.yml"))
        let fixturesDirectory = Self.fixtureURL("depends-completed-compose.yml").deletingLastPathComponent()
        let layers = try ServicePlanner.startupLayers(
            for: fixture,
            projectName: "demo",
            composeDirectory: fixturesDirectory
        )
        expect(layers.count == 2, "completed depends preserves dependency waves")

        let context = HealthWaitContext(services: fixture.services, projectName: "demo")
        let gates = try HealthWait.gatesForNextLayer(nextLayer: layers[1], context: context)
        expect(gates.count == 1, "completed gate count")
        expect(gates[0].dependencyService == "migrate", "completed gate dependency")
        expect(gates[0].condition == .serviceCompletedSuccessfully, "completed gate condition")
        expect(gates[0].containerNames == ["demo_migrate_1"], "completed gate container names")
    }

    mutating func runCompletedDependsWaitSuccessTest() {
        let gate = Self.completedDependsGate()
        let context = Self.completedDependsContext()

        let success = blockingAwait {
            do {
                try await HealthWait.waitForDependencies(
                    gates: [gate],
                    context: context,
                    status: { _ in .running },
                    runProcess: { _, _, _ in 0 },
                    waitForExit: { _ in 0 }
                )
                return true
            } catch {
                return false
            }
        }
        expect(success, "service_completed_successfully succeeds on exit 0")
    }

    mutating func runCompletedDependsWaitFailureTest() {
        let gate = Self.completedDependsGate()
        let context = Self.completedDependsContext()

        let failed = blockingAwait {
            do {
                try await HealthWait.waitForDependencies(
                    gates: [gate],
                    context: context,
                    status: { _ in .running },
                    runProcess: { _, _, _ in 0 },
                    waitForExit: { _ in 1 }
                )
                return false
            } catch ComposeError.serviceCompletedUnsuccessfully {
                return true
            } catch {
                return false
            }
        }
        expect(failed, "service_completed_successfully fails on non-zero exit")
    }

    mutating func runCompletedDependsFastExitTest() {
        let gate = Self.completedDependsGate()
        let context = Self.completedDependsContext()

        let success = blockingAwait {
            do {
                try await HealthWait.waitForDependencies(
                    gates: [gate],
                    context: context,
                    status: { _ in .stopped },
                    runProcess: { _, _, _ in 0 },
                    waitForExit: { _ in 0 }
                )
                return true
            } catch {
                return false
            }
        }
        expect(success, "service_completed_successfully accepts already-stopped dependency")
    }

    mutating func runCompletedDependsWaitTimeoutTest() {
        let gate = Self.completedDependsGate()
        let context = Self.completedDependsContext()
        let timedOut = blockingAwait {
            do {
                try await HealthWait.waitForDependencies(
                    gates: [gate],
                    context: context,
                    status: { _ in .unknown },
                    runProcess: { _, _, _ in 0 },
                    waitForExit: { _ in 0 },
                    completionGateTimeout: .milliseconds(50)
                )
                return false
            } catch ComposeError.serviceCompletionNeverAppeared {
                return true
            } catch {
                return false
            }
        }
        expect(timedOut, "service_completed_successfully errors when dependency never appears")
    }

    mutating func runCompletedDependsExitWaitTimeoutTest() {
        let gate = Self.completedDependsGate()
        let context = Self.completedDependsContext()

        let timedOut = blockingAwait {
            do {
                try await HealthWait.waitForDependencies(
                    gates: [gate],
                    context: context,
                    status: { _ in .running },
                    runProcess: { _, _, _ in 0 },
                    waitForExit: { _ in throw InitExitWait.TimedOut() }
                )
                return false
            } catch ComposeError.serviceCompletionExitTimeout {
                return true
            } catch {
                return false
            }
        }
        expect(timedOut, "service_completed_successfully errors when exit wait exceeds deadline")
    }

    mutating func runCompletedDependsMachinePlanRejectionTest() throws {
        let fixture = try ComposeParser.parse(fileURL: Self.fixtureURL("depends-completed-compose.yml"))
        expectComposeError(
            "service_completed_successfully rejects --machine at plan time",
            matching: {
                if case .machineUnsupportedOperation("depends_on condition service_completed_successfully") = $0 {
                    true
                } else {
                    false
                }
            },
            body: {
                try DependencyValidation.validateMachineMode(
                    services: fixture.services,
                    machineName: "dev"
                )
            }
        )
    }

    mutating func runCompletedDependsMachineRuntimeRejectionTest() {
        let gate = Self.completedDependsGate()
        let context = Self.completedDependsContext()
        let machineContext = MachineContext(machineName: "dev", snapshot: nil)

        let rejected = blockingAwait {
            do {
                try await HealthWait.waitForDependencies(
                    gates: [gate],
                    context: context,
                    machineContext: machineContext,
                    status: { _ in .running }
                )
                return false
            } catch ComposeError.machineUnsupportedOperation(
                "depends_on condition service_completed_successfully"
            ) {
                return true
            } catch {
                return false
            }
        }
        expect(rejected, "service_completed_successfully rejects machine mode at runtime")
    }

    static func completedDependsGate() -> HealthGate {
        HealthGate(
            dependencyService: "migrate",
            condition: .serviceCompletedSuccessfully,
            containerNames: ["demo_migrate_1"]
        )
    }

    static func completedDependsContext() -> HealthWaitContext {
        HealthWaitContext(services: completedDependsServices(), projectName: "demo")
    }

    private static func completedDependsServices() -> [String: ComposeService] {
        [
            "migrate": ComposeService(
                image: "alpine",
                command: nil,
                ports: [],
                environment: nil,
                containerName: nil
            ),
            "app": ComposeService(
                image: "alpine",
                command: nil,
                ports: [],
                environment: nil,
                containerName: nil,
                dependsOn: [
                    ComposeDependency(service: "migrate", condition: .serviceCompletedSuccessfully)
                ]
            )
        ]
    }
}
