import ContainerCommands
import Foundation

extension ServiceRunner {
    package static func upOnHost(
        layers: [[ServicePlan]],
        progress: WaveProgressHandlers? = nil,
        imagePullOutput: ImagePullOutput?,
        healthContext: HealthWaitContext? = nil,
        execution: WaveExecutionPolicy = .unlimited,
        machineContext: MachineContext
    ) async throws {
        let allPlans = layers.flatMap { $0 }
        let hostPullOutput = machineContext.isMachineMode ? nil : imagePullOutput
        try await orchestrateUp(
            layers: layers,
            progress: progress,
            imagePullOutput: hostPullOutput,
            healthContext: healthContext,
            execution: execution,
            hooks: UpOperationHooks(
                runContainer: { plan in
                    try await runContainerWithFileMounts(
                        plan,
                        imagePullOutput: hostPullOutput,
                        machineContext: machineContext
                    )
                },
                rollbackTeardown: { name in
                    if let plan = allPlans.first(where: { $0.name == name }) {
                        ComposeFileStaging.removeContainerStaging(
                            projectName: plan.projectName,
                            containerName: name
                        )
                    }
                    try await ContainerTeardown.teardown(id: name, machineContext: machineContext)
                },
                waitForDependencies: { gates, context in
                    try await HealthWait.waitForDependencies(
                        gates: gates,
                        context: context,
                        machineContext: machineContext
                    )
                }
            )
        )
    }

    package static func runContainerWithFileMounts(
        _ plan: ServicePlan,
        imagePullOutput: ImagePullOutput? = nil,
        machineContext: MachineContext = .applicationSandbox
    ) async throws {
        let machine = machineContext.machineName ?? "host"
        if machineContext.isMachineMode {
            try await ComposeContainerGateway.runDetached(plan: plan, machineContext: machineContext)
            return
        }
        try await ContainerTeardown.teardownRespectingCancellation(id: plan.name, machineContext: machineContext) {
            do {
                let runArguments = try ComposeFileStaging.preparedRunArguments(
                    for: plan,
                    imagePullOutput: imagePullOutput
                )
                let command = try Application.ContainerRun.parse(runArguments)
                try await command.run()
                OsLogTelemetry.enabled {
                    OsLogTelemetry.lifecycle.info(
                        """
                        event=container_start project=\(plan.projectName, privacy: .public) \
                        service=\(plan.serviceName, privacy: .public) \
                        container=\(plan.name, privacy: .public) \
                        replica=\(plan.replicaIndex, privacy: .public) \
                        machine=\(machine, privacy: .public)
                        """
                    )
                }
            } catch {
                ComposeFileStaging.removeContainerStaging(
                    projectName: plan.projectName,
                    containerName: plan.name
                )
                OsLogTelemetry.enabled {
                    OsLogTelemetry.lifecycle.error(
                        """
                        event=container_start_failed project=\(plan.projectName, privacy: .public) \
                        service=\(plan.serviceName, privacy: .public) \
                        container=\(plan.name, privacy: .public) \
                        error_type=\(String(describing: type(of: error)), privacy: .public)
                        """
                    )
                }
                throw error
            }
        }
    }
}
