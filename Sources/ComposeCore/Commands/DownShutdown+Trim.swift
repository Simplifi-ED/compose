import Foundation

extension DownShutdown {
    package static func finishProjectTrim(_ input: FinishTeardownInput) async {
        guard input.shouldTrim else { return }
        await SignpostTelemetry.interval(SignpostTelemetry.volume, category: .volumes) {
            if let warning = await DiskTrim.trimMachineGuestAfterProjectTeardown(
                projectName: input.context.projectName,
                machineContext: input.machineContext
            ) {
                DiskTrim.emitWarnings([warning])
            }
        }
    }

    static func tearDownContainers(
        context: ProjectOptions.LabelCommandContext,
        containers: [DiscoveredContainer],
        useOrderedShutdown: Bool,
        progress: WaveProgressHandlers?,
        execution: WaveExecutionPolicy = .unlimited,
        machineContext: MachineContext = .applicationSandbox,
        trimBeforeDelete: Bool = false
    ) async throws {
        let layers = try resolveShutdownLayers(
            context: context,
            containers: containers,
            useOrderedShutdown: useOrderedShutdown
        )
        try await ServiceRunner.orchestrateDown(
            layers: layers,
            projectName: context.projectName,
            onRemoved: { print($0) },
            progress: progress,
            execution: execution,
            teardown: { container in
                if trimBeforeDelete {
                    if let warning = await DiskTrim.trimContainerBeforeDelete(
                        containerID: container.name,
                        projectName: context.projectName,
                        machineContext: machineContext
                    ) {
                        DiskTrim.emitWarnings([warning])
                    }
                }
                try await ContainerTeardown.teardownRespectingCancellation(
                    id: container.name,
                    machineContext: machineContext
                )
                ComposeFileStaging.removeContainerStaging(
                    projectName: context.projectName,
                    containerName: container.name
                )
            }
        )
    }
}
