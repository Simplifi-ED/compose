import Foundation

extension ServiceRunner {
    private struct StartupWaveRequest {
        let index: Int
        let layer: [ServicePlan]
        let layers: [[ServicePlan]]
        let progress: WaveProgressHandlers?
        let healthContext: HealthWaitContext?
        let execution: WaveExecutionPolicy
        let hooks: UpOperationHooks
        let beforeWave: (@Sendable (Int) async -> Void)?
    }

    package static func orchestrateUp(
        layers: [[ServicePlan]],
        progress: WaveProgressHandlers?,
        healthContext: HealthWaitContext?,
        execution: WaveExecutionPolicy = .unlimited,
        hooks: UpOperationHooks,
        beforeWave: (@Sendable (Int) async -> Void)? = nil
    ) async throws {
        var startedWaves: [[String]] = []
        do {
            for (index, layer) in layers.enumerated() {
                try await runStartupWave(
                    StartupWaveRequest(
                        index: index,
                        layer: layer,
                        layers: layers,
                        progress: progress,
                        healthContext: healthContext,
                        execution: execution,
                        hooks: hooks,
                        beforeWave: beforeWave
                    ),
                    startedWaves: &startedWaves
                )
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try await handleUpOrchestrationFailure(
                error: error,
                startedWaves: startedWaves,
                layers: layers,
                execution: execution,
                rollbackTeardown: hooks.rollbackTeardown
            )
        }
    }

    private static func runStartupWave(
        _ request: StartupWaveRequest,
        startedWaves: inout [[String]]
    ) async throws {
        try Task.checkCancellation()
        await request.beforeWave?(request.index)
        let project = request.layer.first?.projectName ?? ""
        await request.progress?.onWaveStart?(
            request.index + 1,
            request.layers.count,
            request.layer.map(\.name)
        )
        logWaveStart(
            wave: request.index + 1,
            total: request.layers.count,
            project: project,
            containerNames: request.layer.map(\.name)
        )
        let result = await parallelRun(
            request.layer.map {
                ParallelRunItem(label: $0.name, collectOnSuccess: $0.name, value: $0)
            },
            maxConcurrent: request.execution.maxConcurrent,
            onCompletion: request.progress?.onServiceComplete
        ) { plan in
            try await request.hooks.runContainer(plan)
        }
        if result.wasInterrupted {
            handleInterruptedWave(
                result: result,
                startedWaves: &startedWaves,
                layers: request.layers
            )
            throw CancellationError()
        }
        if !result.succeeded.isEmpty {
            startedWaves.append(result.succeeded)
        }
        try handleStartupWaveFailures(
            result: result,
            index: request.index,
            project: project
        )
        await request.progress?.onWaveComplete?(request.index + 1)
        logWaveComplete(wave: request.index + 1, project: project)
        try await waitForNextLayerHealth(request: request)
    }

    private static func handleStartupWaveFailures(
        result: ParallelRunResult,
        index: Int,
        project: String
    ) throws {
        if !result.failures.isEmpty {
            logWaveFailure(wave: index + 1, project: project, failures: result.failures)
            throw ComposeError.multipleServiceFailures(result.failures)
        }
    }

    private static func waitForNextLayerHealth(
        request: StartupWaveRequest
    ) async throws {
        guard let healthContext = request.healthContext,
              request.index + 1 < request.layers.count
        else { return }
        let gates = try HealthWait.gatesForNextLayer(
            nextLayer: request.layers[request.index + 1],
            context: healthContext
        )
        try await request.hooks.waitForDependencies(gates, healthContext)
    }
}
