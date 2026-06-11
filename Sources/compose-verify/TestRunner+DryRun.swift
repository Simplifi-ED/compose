import ComposeCore
import Foundation

extension TestRunner {
    mutating func runDryRunTests() throws {
        try runDryRunUpTests()
        try runDryRunHealthWaitTests()
        try runDryRunScaleTests()
        try runDryRunOrphanTests()
        try runDryRunDownTests()
        try runDryRunVolumePurgeTests()
        try runDryRunRunTests()
        runDryRunExecTests()
        try runDryRunPlanningValidationTests()
    }

    func dryRunUpResult(
        layers: [[ServicePlan]],
        healthContext: HealthWaitContext? = nil,
        manifest: DryRunManifest
    ) -> (completed: Bool, lines: [String]) {
        let hooks = blockingAwait { await manifest.makeUpHooks() }
        let completed = blockingAwait {
            do {
                try await ServiceRunner.up(
                    layers: layers,
                    healthContext: healthContext,
                    hooks: hooks,
                    beforeWave: { index in
                        await manifest.setUpWaveIndex(index)
                    }
                )
                return true
            } catch {
                return false
            }
        }
        let lines = blockingAwait { await manifest.sortedLines() }
        return (completed, lines)
    }

    func dryRunDownResult(
        layers: [[DiscoveredContainer]],
        manifest: DryRunManifest,
        execution: WaveExecutionPolicy = .unlimited
    ) -> (completed: Bool, lines: [String]) {
        let teardown = blockingAwait { await manifest.makeDownTeardown() }
        let completed = blockingAwait {
            do {
                try await ServiceRunner.orchestrateDown(
                    layers: layers,
                    onRemoved: nil,
                    progress: nil,
                    execution: execution,
                    teardown: teardown,
                    beforeWave: { index in
                        await manifest.setDownWaveIndex(index)
                    }
                )
                return true
            } catch {
                return false
            }
        }
        let lines = blockingAwait { await manifest.sortedLines() }
        return (completed, lines)
    }

    func dryRunManifestLines(
        manifest: DryRunManifest,
        record: @escaping @Sendable (DryRunManifest) async -> Void
    ) -> [String] {
        blockingAwait {
            await record(manifest)
        }
        return blockingAwait { await manifest.sortedLines() }
    }
}
