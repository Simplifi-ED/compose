import Foundation

/// Delta replica reconcile for `compose scale` — start missing indices, stop excess; no teardown within desired count.
package enum ScaleReconcile {
    package struct Plan: Sendable {
        package let toStart: [ServicePlan]
        package let toStop: [String]

        package init(toStart: [ServicePlan], toStop: [String]) {
            self.toStart = toStart
            self.toStop = toStop
        }
    }

    package static func execute(
        plan: Plan,
        projectName: String,
        imagePullOutput: ImagePullOutput?,
        machineContext: MachineContext,
        maxConcurrent: Int? = nil
    ) async throws -> [String] {
        let policy = WaveExecutionPolicy(maxConcurrent: maxConcurrent)
        var affected = try await stopExcess(
            names: plan.toStop,
            projectName: projectName,
            machineContext: machineContext,
            maxConcurrent: policy.maxConcurrent
        )
        guard !plan.toStart.isEmpty else { return affected }

        let hostPullOutput = machineContext.isMachineMode ? nil : imagePullOutput
        if let hostPullOutput {
            try await ImagePullRunner.pullMissing(
                plans: plan.toStart,
                output: hostPullOutput,
                maxConcurrent: policy.maxConcurrent
            )
        }
        let started = try await startMissing(
            plans: plan.toStart,
            imagePullOutput: hostPullOutput,
            machineContext: machineContext,
            maxConcurrent: policy.maxConcurrent
        )
        affected.append(contentsOf: started)
        return affected
    }

    private static func stopExcess(
        names: [String],
        projectName: String,
        machineContext: MachineContext,
        maxConcurrent: Int?
    ) async throws -> [String] {
        guard !names.isEmpty else { return [] }
        let stopResult = await ServiceRunner.parallelRun(
            names.map {
                ServiceRunner.ParallelRunItem(label: $0, collectOnSuccess: $0, value: $0)
            },
            maxConcurrent: maxConcurrent
        ) { name in
            ComposeFileStaging.removeContainerStaging(
                projectName: projectName,
                containerName: name
            )
            try await ContainerTeardown.teardown(id: name, machineContext: machineContext)
        }
        if !stopResult.failures.isEmpty {
            throw ComposeError.multipleServiceFailures(stopResult.failures)
        }
        return stopResult.succeeded
    }

    private static func startMissing(
        plans: [ServicePlan],
        imagePullOutput: ImagePullOutput?,
        machineContext: MachineContext,
        maxConcurrent: Int?
    ) async throws -> [String] {
        let startResult = await ServiceRunner.parallelRun(
            plans.map {
                ServiceRunner.ParallelRunItem(label: $0.name, collectOnSuccess: $0.name, value: $0)
            },
            maxConcurrent: maxConcurrent
        ) { servicePlan in
            try await ServiceRunner.runContainerWithFileMounts(
                servicePlan,
                imagePullOutput: imagePullOutput,
                machineContext: machineContext
            )
        }
        if !startResult.failures.isEmpty {
            throw ComposeError.multipleServiceFailures(startResult.failures)
        }
        return startResult.succeeded
    }
}
