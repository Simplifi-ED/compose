import Foundation

extension ServiceRunner {
    package static func runContainerWaves(
        layers: [[DiscoveredContainer]],
        projectName: String = "",
        progress: WaveProgressHandlers?,
        failFast: Bool,
        execution: WaveExecutionPolicy = .unlimited,
        beforeWave: (@Sendable (Int) async -> Void)? = nil,
        work: @escaping @Sendable (DiscoveredContainer) async throws -> Void,
        onWaveComplete: @escaping @Sendable ([DiscoveredContainer]) async -> Void
    ) async throws -> [(name: String, error: Error)] {
        var collectedFailures: [(name: String, error: Error)] = []

        for (index, layer) in layers.enumerated() {
            try await runShutdownWave(
                ShutdownWaveRequest(
                    index: index,
                    layer: layer,
                    layers: layers,
                    projectName: projectName,
                    progress: progress,
                    failFast: failFast,
                    execution: execution,
                    beforeWave: beforeWave,
                    work: work,
                    onWaveComplete: onWaveComplete
                ),
                collectedFailures: &collectedFailures
            )
        }

        return collectedFailures
    }

    private struct ShutdownWaveRequest {
        let index: Int
        let layer: [DiscoveredContainer]
        let layers: [[DiscoveredContainer]]
        let projectName: String
        let progress: WaveProgressHandlers?
        let failFast: Bool
        let execution: WaveExecutionPolicy
        let beforeWave: (@Sendable (Int) async -> Void)?
        let work: @Sendable (DiscoveredContainer) async throws -> Void
        let onWaveComplete: @Sendable ([DiscoveredContainer]) async -> Void
    }

    private static func runShutdownWave(
        _ request: ShutdownWaveRequest,
        collectedFailures: inout [(name: String, error: Error)]
    ) async throws {
        try Task.checkCancellation()
        await request.beforeWave?(request.index)
        await request.progress?.onWaveStart?(
            request.index + 1,
            request.layers.count,
            request.layer.map(\.name)
        )
        logWaveStart(
            wave: request.index + 1,
            total: request.layers.count,
            project: request.projectName,
            containerNames: request.layer.map(\.name)
        )
        let result = await parallelRun(
            request.layer.map { ParallelRunItem(label: $0.name, collectOnSuccess: nil, value: $0) },
            maxConcurrent: request.execution.maxConcurrent,
            onCompletion: request.progress?.onServiceComplete
        ) { container in
            try await request.work(container)
        }
        if result.wasInterrupted {
            let removed = request.layer.filter { result.completed.contains($0.name) }
            if !removed.isEmpty {
                await request.onWaveComplete(removed)
            }
            throw CancellationError()
        }
        if !result.failures.isEmpty {
            try handleShutdownWaveFailures(
                result: result,
                request: request,
                collectedFailures: &collectedFailures
            )
        }
        await request.progress?.onWaveComplete?(request.index + 1)
        logWaveComplete(wave: request.index + 1, project: request.projectName)
        await request.onWaveComplete(request.layer)
    }

    private static func handleShutdownWaveFailures(
        result: ParallelRunResult,
        request: ShutdownWaveRequest,
        collectedFailures: inout [(name: String, error: Error)]
    ) throws {
        guard !result.failures.isEmpty else { return }
        logWaveFailure(
            wave: request.index + 1,
            project: request.projectName,
            failures: result.failures
        )
        if request.failFast {
            let remaining = request.layers.count - request.index - 1
            if remaining > 0 {
                fputs(
                    """
                    Warning: compose down failed in wave \(request.index + 1) of \(request.layers.count); \
                    \(remaining) later wave(s) were not run.\n
                    """,
                    stderr
                )
            }
            throw ComposeError.multipleServiceFailures(result.failures)
        }
        collectedFailures.append(
            contentsOf: result.failures.map { (name: $0.service, error: $0.error) }
        )
    }
}
