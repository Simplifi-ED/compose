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

    public static func up(plans: [ServicePlan]) async throws {
        try await up(layers: [plans])
    }

    public static func up(
        layers: [[ServicePlan]],
        progress: WaveProgressHandlers? = nil,
        healthContext: HealthWaitContext? = nil,
        execution: WaveExecutionPolicy = .unlimited
    ) async throws {
        let allPlans = layers.flatMap { $0 }
        try await orchestrateUp(
            layers: layers,
            progress: progress,
            healthContext: healthContext,
            execution: execution,
            hooks: UpOperationHooks(
                runContainer: { plan in
                    try await runContainerWithFileMounts(plan)
                },
                rollbackTeardown: { name in
                    if let plan = allPlans.first(where: { $0.name == name }) {
                        ComposeFileStaging.removeContainerStaging(
                            projectName: plan.projectName,
                            containerName: name
                        )
                    }
                    try await ContainerTeardown.teardown(id: name)
                },
                waitForDependencies: { gates, context in
                    try await HealthWait.waitForDependencies(gates: gates, context: context)
                }
            )
        )
    }

    /// compose-verify entry point for orchestration with injected health waits.
    package static func up(
        layers: [[ServicePlan]],
        healthContext: HealthWaitContext?,
        hooks: UpOperationHooks,
        execution: WaveExecutionPolicy = .unlimited
    ) async throws {
        try await orchestrateUp(
            layers: layers,
            progress: nil,
            healthContext: healthContext,
            execution: execution,
            hooks: hooks
        )
    }

    package static func runContainerWithFileMounts(_ plan: ServicePlan) async throws {
        try await ContainerTeardown.teardownRespectingCancellation(id: plan.name) {
            let runArguments = try ComposeFileStaging.preparedRunArguments(for: plan)
            let command: Application.ContainerRun
            do {
                command = try Application.ContainerRun.parse(runArguments)
            } catch {
                ComposeFileStaging.removeContainerStaging(
                    projectName: plan.projectName,
                    containerName: plan.name
                )
                throw error
            }
            try await command.run()
        }
    }

    package static func orchestrateUp(
        layers: [[ServicePlan]],
        progress: WaveProgressHandlers?,
        healthContext: HealthWaitContext?,
        execution: WaveExecutionPolicy = .unlimited,
        hooks: UpOperationHooks
    ) async throws {
        var startedWaves: [[String]] = []
        do {
            for (index, layer) in layers.enumerated() {
                try Task.checkCancellation()
                // Progress keys on container names so replicas of one service stay distinct.
                await progress?.onWaveStart?(index + 1, layers.count, layer.map(\.name))
                let result = await parallelRun(
                    layer.map { ParallelRunItem(label: $0.name, collectOnSuccess: $0.name, value: $0) },
                    maxConcurrent: execution.maxConcurrent,
                    onCompletion: progress?.onServiceComplete
                ) { plan in
                    try await hooks.runContainer(plan)
                }
                if result.wasInterrupted {
                    handleInterruptedWave(result: result, startedWaves: &startedWaves, layers: layers)
                    throw CancellationError()
                }
                if !result.succeeded.isEmpty {
                    startedWaves.append(result.succeeded)
                }
                if !result.failures.isEmpty {
                    throw ComposeError.multipleServiceFailures(result.failures)
                }
                await progress?.onWaveComplete?(index + 1)

                if let healthContext, index + 1 < layers.count {
                    let gates = try HealthWait.gatesForNextLayer(
                        nextLayer: layers[index + 1],
                        context: healthContext
                    )
                    try await hooks.waitForDependencies(gates, healthContext)
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Roll back in reverse startup order; parallel within each wave.
            let rollbackFailures = await rollbackStartedContainers(
                startedWaves.reversed(),
                execution: execution,
                teardown: hooks.rollbackTeardown
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

    public static func down(
        containers: [DiscoveredContainer],
        projectName: String? = nil,
        onRemoved: (@Sendable (String) -> Void)? = nil,
        progress: WaveProgressHandlers? = nil,
        execution: WaveExecutionPolicy = .unlimited
    ) async throws {
        try await down(
            layers: [containers],
            projectName: projectName,
            onRemoved: onRemoved,
            progress: progress,
            execution: execution
        )
    }

    public static func down(
        layers: [[DiscoveredContainer]],
        projectName: String? = nil,
        onRemoved: (@Sendable (String) -> Void)? = nil,
        progress: WaveProgressHandlers? = nil,
        execution: WaveExecutionPolicy = .unlimited
    ) async throws {
        try await orchestrateDown(
            layers: layers,
            onRemoved: onRemoved,
            progress: progress,
            execution: execution,
            teardown: { container in
                try await ContainerTeardown.teardownRespectingCancellation(id: container.name)
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
        onRemoved: (@Sendable (String) -> Void)?,
        progress: WaveProgressHandlers?,
        execution: WaveExecutionPolicy = .unlimited,
        teardown: @escaping @Sendable (DiscoveredContainer) async throws -> Void
    ) async throws {
        _ = try await runContainerWaves(
            layers: layers,
            progress: progress,
            failFast: true,
            execution: execution
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

    /// SIGTERM each container with grace, then SIGKILL. Collects per-container failures.
    package static func stopGracefully(
        layers: [[DiscoveredContainer]],
        options: GracefulStopOptions
    ) async throws -> [(name: String, error: Error)] {
        try await runContainerWaves(
            layers: layers,
            progress: nil,
            failFast: false
        ) { container in
            try await ContainerTeardown.stopGracefully(id: container.name, options: options)
        } onWaveComplete: { _ in }
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
