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
}
