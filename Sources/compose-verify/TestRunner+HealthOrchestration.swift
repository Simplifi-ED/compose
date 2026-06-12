import ComposeCore
import Foundation

extension TestRunner {
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
                    hooks: ServiceRunner.UpOperationHooks(
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
                                runProcess: { _, _, _ in 0 }
                            )
                        }
                    )
                )
                return true
            } catch {
                return false
            }
        }

        let started = blockingAwait { await recorder.startedSnapshot() }
        let waits = blockingAwait { await recorder.waitSnapshot() }
        let rollback = blockingAwait { await recorder.rollbackSnapshot() }
        expect(success, "health orchestration completes")
        expect(started == ["demo_db_1", "demo_web_1"], "health orchestration startup order")
        expect(waits.count == 1, "health wait runs between waves")
        expect(waits[0].first?.dependencyService == "db", "health wait targets dependency")
        expect(rollback.isEmpty, "successful health orchestration does not roll back")

        runHealthOrchestrationRollbackTests(dbPlan: dbPlan, webPlan: webPlan, context: context)
        runCompletedDependsOrchestrationRollbackTests()
    }

    mutating func runCompletedDependsOrchestrationRollbackTests() {
        let migratePlan = ServicePlan(serviceName: "migrate", name: "demo_migrate_1", runArguments: [])
        let appPlan = ServicePlan(serviceName: "app", name: "demo_app_1", runArguments: [])
        let context = Self.completedDependsContext()
        let rollbackRecorder = HealthOrchestrationRecorder()
        let hooks = Self.completedDependsFailureHooks(recorder: rollbackRecorder)

        let completionFailed = blockingAwait {
            do {
                try await ServiceRunner.up(
                    layers: [[migratePlan], [appPlan]],
                    healthContext: context,
                    hooks: hooks
                )
                return false
            } catch ComposeError.serviceCompletedUnsuccessfully {
                return true
            } catch {
                return false
            }
        }
        let rolledBack = blockingAwait { await rollbackRecorder.rollbackSnapshot() }
        expect(completionFailed, "completion failure fails orchestration")
        expect(rolledBack == ["demo_migrate_1"], "completion failure rolls back prior wave")
    }

    private static func completedDependsFailureHooks(
        recorder: HealthOrchestrationRecorder
    ) -> ServiceRunner.UpOperationHooks {
        ServiceRunner.UpOperationHooks(
            runContainer: { plan in
                await recorder.recordStarted(plan.name)
            },
            rollbackTeardown: { name in
                await recorder.recordRollback(name)
            },
            waitForDependencies: { gates, waitContext in
                try await HealthWait.waitForDependencies(
                    gates: gates,
                    context: waitContext,
                    status: { _ in .running },
                    runProcess: { _, _, _ in 0 },
                    waitForExit: { _ in 1 }
                )
            }
        )
    }

    private mutating func runHealthOrchestrationRollbackTests(
        dbPlan: ServicePlan,
        webPlan: ServicePlan,
        context: HealthWaitContext
    ) {
        let rollbackRecorder = HealthOrchestrationRecorder()
        let healthFailed = blockingAwait {
            do {
                try await ServiceRunner.up(
                    layers: [[dbPlan], [webPlan]],
                    healthContext: context,
                    hooks: ServiceRunner.UpOperationHooks(
                        runContainer: { plan in
                            await rollbackRecorder.recordStarted(plan.name)
                        },
                        rollbackTeardown: { name in
                            await rollbackRecorder.recordRollback(name)
                        },
                        waitForDependencies: { gates, waitContext in
                            try await HealthWait.waitForDependencies(
                                gates: gates,
                                context: waitContext,
                                status: { _ in .running },
                                runProcess: { _, _, _ in 1 }
                            )
                        }
                    )
                )
                return false
            } catch ComposeError.healthCheckTimeout {
                return true
            } catch {
                return false
            }
        }
        let rolledBack = blockingAwait { await rollbackRecorder.rollbackSnapshot() }
        expect(healthFailed, "health timeout fails orchestration")
        expect(rolledBack == ["demo_db_1"], "health timeout rolls back prior wave")
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

    func rollbackSnapshot() -> [String] {
        rollback
    }

    func waitSnapshot() -> [[HealthGate]] {
        waits
    }
}
