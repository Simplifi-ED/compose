import Foundation

package enum ServiceRunnerRestart {
    /// Recreates only the given containers (watch sync+restart); no project-wide teardown.
    package static func restartPlans(
        _ plans: [ServicePlan],
        runContainer: @Sendable @escaping (ServicePlan) async throws -> Void = { plan in
            try await ServiceRunner.runContainerWithFileMounts(plan)
        }
    ) async throws {
        guard !plans.isEmpty else { return }
        let result = await ServiceRunner.parallelRun(
            plans.map { ServiceRunner.ParallelRunItem(label: $0.name, collectOnSuccess: $0.name, value: $0) },
            maxConcurrent: WaveExecutionPolicy.unlimited.maxConcurrent
        ) { plan in
            try await runContainer(plan)
        }
        if !result.failures.isEmpty {
            throw ComposeError.multipleServiceFailures(result.failures)
        }
    }
}
