import Foundation

package struct ProjectDownRequest: Sendable {
    package let inputs: ComposeCommandInputs
    package let dryRun: Bool
    package let removeVolumes: Bool
    package let trim: Bool
    package let maxConcurrent: Int?

    package init(
        inputs: ComposeCommandInputs,
        dryRun: Bool = false,
        removeVolumes: Bool = false,
        trim: Bool = false,
        maxConcurrent: Int? = nil
    ) {
        self.inputs = inputs
        self.dryRun = dryRun
        self.removeVolumes = removeVolumes
        self.trim = trim
        self.maxConcurrent = maxConcurrent
    }
}

package enum ProjectDownRun {
    package static func run(_ request: ProjectDownRequest) async throws -> ComposeXPCMutationResponse {
        let shutdown = try await resolveShutdown(request: request)
        if request.dryRun {
            return ComposeXPCMutationResponse(
                exitStatus: 0,
                affectedContainers: shutdown.containers.map(\.name)
            )
        }
        try await executeShutdown(request: request, shutdown: shutdown)
        return ComposeXPCMutationResponse(
            exitStatus: 0,
            affectedContainers: shutdown.containers.map(\.name)
        )
    }

    private struct ShutdownContext: Sendable {
        let machineContext: MachineContext
        let labelContext: ProjectOptions.LabelCommandContext
        let discovered: [DiscoveredContainer]
        let containers: [DiscoveredContainer]
    }

    private static func resolveShutdown(request: ProjectDownRequest) async throws -> ShutdownContext {
        var machineContext = try await MachineContext.resolve(machineName: request.inputs.machineName)
        if machineContext.isMachineMode, !request.dryRun, !machineContext.isMachineRunning {
            machineContext = try await machineContext.ensureBooted()
        }
        let context = try await ComposeCommandContext.resolveLabelContext(inputs: request.inputs)
        let discovered = try await ContainerDiscovery.containers(
            forProject: context.projectName,
            machineContext: machineContext
        )
        let downProfile = try ComposeCommandContext.downServiceFilter(
            context: context,
            inputs: request.inputs
        )
        let containers = try DownShutdown.filteredContainers(
            discovered: discovered,
            context: context,
            profileFilterRequested: downProfile.profileFilterRequested,
            activeProfiles: ProfileResolution.resolve(
                cliProfiles: request.inputs.profiles,
                environment: request.inputs.environment
            ).activeProfiles,
            tearsDownAll: downProfile.tearsDownAll
        )
        return ShutdownContext(
            machineContext: machineContext,
            labelContext: context,
            discovered: discovered,
            containers: containers
        )
    }

    private static func executeShutdown(
        request: ProjectDownRequest,
        shutdown: ShutdownContext
    ) async throws {
        let hasExplicitProject = request.inputs.projectName.map { !$0.isEmpty } ?? false
        let useOrderedShutdown = shutdown.labelContext.fileURLs != nil && !hasExplicitProject
        let volumePurgeContext = DownShutdown.volumePurgeContext(
            context: shutdown.labelContext,
            discovered: shutdown.discovered,
            teardownContainers: shutdown.containers
        )
        let execution = WaveExecutionPolicy(maxConcurrent: request.maxConcurrent)
        try await DownShutdown.tearDownContainers(
            context: shutdown.labelContext,
            containers: shutdown.containers,
            useOrderedShutdown: useOrderedShutdown,
            progress: nil,
            execution: execution,
            machineContext: shutdown.machineContext,
            trimBeforeDelete: request.trim
        )
        try await DownShutdown.finishProjectTeardown(
            DownShutdown.FinishTeardownInput(
                context: shutdown.labelContext,
                discovered: shutdown.discovered,
                teardownContainers: shutdown.containers,
                shouldPurgeVolumes: request.removeVolumes,
                shouldTrim: request.trim,
                bindPurgeContext: volumePurgeContext,
                machineContext: shutdown.machineContext
            )
        )
    }
}
