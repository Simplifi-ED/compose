import ContainerCommands
import Foundation

public enum ServiceRunner {
    package struct UpOperationHooks: Sendable {
        package let runContainer: @Sendable (ServicePlan) async throws -> Void
        package let rollbackTeardown: @Sendable (String) async throws -> Void
        package let waitForDependencies: @Sendable ([HealthGate], HealthWaitContext) async throws -> Void

        package init(
            runContainer: @escaping @Sendable (ServicePlan) async throws -> Void,
            rollbackTeardown: @escaping @Sendable (String) async throws -> Void,
            waitForDependencies: @escaping @Sendable ([HealthGate], HealthWaitContext) async throws -> Void
        ) {
            self.runContainer = runContainer
            self.rollbackTeardown = rollbackTeardown
            self.waitForDependencies = waitForDependencies
        }
    }

    public static func up(
        plans: [ServicePlan],
        machineContext: MachineContext = .applicationSandbox
    ) async throws {
        try await up(layers: [plans], machineContext: machineContext)
    }

    public static func up(
        layers: [[ServicePlan]],
        progress: WaveProgressHandlers? = nil,
        healthContext: HealthWaitContext? = nil,
        execution: WaveExecutionPolicy = .unlimited,
        machineContext: MachineContext = .applicationSandbox
    ) async throws {
        let allPlans = layers.flatMap { $0 }
        try await orchestrateUp(
            layers: layers,
            progress: progress,
            healthContext: healthContext,
            execution: execution,
            hooks: UpOperationHooks(
                runContainer: { plan in
                    try await runContainerWithFileMounts(plan, machineContext: machineContext)
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

    /// Injected orchestration for compose-verify and dry-run.
    package static func up(
        layers: [[ServicePlan]],
        healthContext: HealthWaitContext?,
        hooks: UpOperationHooks,
        execution: WaveExecutionPolicy = .unlimited,
        beforeWave: (@Sendable (Int) async -> Void)? = nil
    ) async throws {
        try await orchestrateUp(
            layers: layers,
            progress: nil,
            healthContext: healthContext,
            execution: execution,
            hooks: hooks,
            beforeWave: beforeWave
        )
    }

    package static func runContainerWithFileMounts(
        _ plan: ServicePlan,
        machineContext: MachineContext = .applicationSandbox
    ) async throws {
        let machine = machineContext.machineName ?? "host"
        if machineContext.isMachineMode {
            try await ComposeContainerGateway.runDetached(plan: plan, machineContext: machineContext)
            return
        }
        try await ContainerTeardown.teardownRespectingCancellation(id: plan.name, machineContext: machineContext) {
            let runArguments = try ComposeFileStaging.preparedRunArguments(for: plan)
            let command: Application.ContainerRun
            do {
                command = try Application.ContainerRun.parse(runArguments)
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
        }
    }

    public static func down(
        containers: [DiscoveredContainer],
        projectName: String? = nil,
        onRemoved: (@Sendable (String) -> Void)? = nil,
        progress: WaveProgressHandlers? = nil,
        execution: WaveExecutionPolicy = .unlimited,
        machineContext: MachineContext = .applicationSandbox
    ) async throws {
        try await down(
            layers: [containers],
            projectName: projectName,
            onRemoved: onRemoved,
            progress: progress,
            execution: execution,
            machineContext: machineContext
        )
    }

    public static func down(
        layers: [[DiscoveredContainer]],
        projectName: String? = nil,
        onRemoved: (@Sendable (String) -> Void)? = nil,
        progress: WaveProgressHandlers? = nil,
        execution: WaveExecutionPolicy = .unlimited,
        machineContext: MachineContext = .applicationSandbox
    ) async throws {
        try await orchestrateDown(
            layers: layers,
            projectName: projectName ?? "",
            onRemoved: onRemoved,
            progress: progress,
            execution: execution,
            teardown: { container in
                try await ContainerTeardown.teardownRespectingCancellation(
                    id: container.name,
                    machineContext: machineContext
                )
                if let projectName {
                    ComposeFileStaging.removeContainerStaging(
                        projectName: projectName,
                        containerName: container.name
                    )
                }
            }
        )
    }

    package static func orchestrateDown(
        layers: [[DiscoveredContainer]],
        projectName: String = "",
        onRemoved: (@Sendable (String) -> Void)?,
        progress: WaveProgressHandlers?,
        execution: WaveExecutionPolicy = .unlimited,
        teardown: @escaping @Sendable (DiscoveredContainer) async throws -> Void,
        beforeWave: (@Sendable (Int) async -> Void)? = nil
    ) async throws {
        _ = try await runContainerWaves(
            layers: layers,
            projectName: projectName,
            progress: progress,
            failFast: true,
            execution: execution,
            beforeWave: beforeWave
        ) { container in
            try await teardown(container)
        } onWaveComplete: { layer in
            if let onRemoved {
                for container in layer {
                    onRemoved(container.name)
                }
            }
        }
    }

    public static func rollbackStartedContainers(
        _ waves: [[String]],
        execution: WaveExecutionPolicy = .unlimited,
        teardown: @escaping @Sendable (String) async throws -> Void = { name in
            try await ContainerTeardown.teardown(id: name)
        }
    ) async -> [(container: String, error: Error)] {
        var failures: [(container: String, error: Error)] = []
        for wave in waves {
            if Task.isCancelled {
                break
            }
            guard !wave.isEmpty else { continue }
            let result = await parallelRun(
                wave.map { ParallelRunItem(label: $0, collectOnSuccess: nil, value: $0) },
                maxConcurrent: execution.maxConcurrent
            ) { name in
                try await ContainerTeardown.teardownRespectingCancellation(id: name) {
                    try await teardown(name)
                }
            }
            if result.wasInterrupted {
                break
            }
            failures.append(contentsOf: result.failures.map { (container: $0.service, error: $0.error) })
        }
        return failures
    }
}
