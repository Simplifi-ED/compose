import Foundation

extension ServiceRunner {
    package static func cleanupOrphanStaging(layers: [[ServicePlan]], startedWaves: [[String]]) {
        let started = Set(startedWaves.flatMap { $0 })
        for plan in layers.flatMap({ $0 }) where !started.contains(plan.name) {
            ComposeFileStaging.removeContainerStaging(
                projectName: plan.projectName,
                containerName: plan.name
            )
        }
    }

    static func handleInterruptedWave(
        result: ParallelRunResult,
        startedWaves: inout [[String]],
        layers: [[ServicePlan]]
    ) {
        if !result.succeeded.isEmpty {
            startedWaves.append(result.succeeded)
        }
        cleanupOrphanStaging(layers: layers, startedWaves: startedWaves)
    }

    static func handleUpOrchestrationFailure(
        error: Error,
        startedWaves: [[String]],
        layers: [[ServicePlan]],
        execution: WaveExecutionPolicy,
        rollbackTeardown: @Sendable @escaping (String) async throws -> Void
    ) async throws {
        let rollbackFailures = await rollbackStartedContainers(
            startedWaves.reversed(),
            execution: execution,
            teardown: rollbackTeardown
        )
        cleanupOrphanStaging(layers: layers, startedWaves: startedWaves)
        if !rollbackFailures.isEmpty {
            let started = startedWaves.flatMap { $0 }
            let rollbackMessage = ComposeError.rollbackFailed(
                started: started,
                failures: rollbackFailures
            ).localizedDescription
            fputs("Warning: \(rollbackMessage)\n", stderr)
        }
        throw error
    }
}
