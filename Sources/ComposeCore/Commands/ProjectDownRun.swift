import Foundation

package struct ProjectDownRequest: Sendable {
    package let inputs: ComposeCommandInputs
    package let dryRun: Bool
    package let removeVolumes: Bool
    package let trim: Bool
    package let maxConcurrent: Int?
    package let orphanPolicy: ProjectDownOrphanPolicy?

    package init(
        inputs: ComposeCommandInputs,
        dryRun: Bool = false,
        removeVolumes: Bool = false,
        trim: Bool = false,
        maxConcurrent: Int? = nil,
        orphanPolicy: ProjectDownOrphanPolicy? = nil
    ) {
        self.inputs = inputs
        self.dryRun = dryRun
        self.removeVolumes = removeVolumes
        self.trim = trim
        self.maxConcurrent = maxConcurrent
        self.orphanPolicy = orphanPolicy
    }
}

package struct ProjectDownOrphanPolicy: Sendable {
    package let profileFilterRequested: Bool
    package let tearsDownAll: Bool
    package let activeProfiles: Set<String>

    package init(
        profileFilterRequested: Bool,
        tearsDownAll: Bool,
        activeProfiles: Set<String>
    ) {
        self.profileFilterRequested = profileFilterRequested
        self.tearsDownAll = tearsDownAll
        self.activeProfiles = activeProfiles
    }
}

package struct ProjectDownExecution: Sendable {
    package let progress: WaveProgressHandlers?

    package init(progress: WaveProgressHandlers? = nil) {
        self.progress = progress
    }
}

package enum ProjectDownRun {
    package struct ShutdownContext: Sendable {
        package let machineContext: MachineContext
        package let labelContext: ProjectOptions.LabelCommandContext
        package let discovered: [DiscoveredContainer]
        package let containers: [DiscoveredContainer]
        package let orphanNames: Set<String>
    }

    package static func run(
        _ request: ProjectDownRequest,
        execution: ProjectDownExecution = ProjectDownExecution()
    ) async throws -> ProjectMutationResult {
        let shutdown = try await resolveShutdown(request: request)
        if request.dryRun {
            return ProjectMutationResult(affectedContainers: shutdown.containers.map(\.name))
        }
        try await executeShutdown(request: request, shutdown: shutdown, execution: execution)
        return ProjectMutationResult(affectedContainers: shutdown.containers.map(\.name))
    }

    package static func resolveShutdown(request: ProjectDownRequest) async throws -> ShutdownContext {
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
        let selected = try DownShutdown.filteredContainers(
            discovered: discovered,
            context: context,
            profileFilterRequested: downProfile.profileFilterRequested,
            activeProfiles: ProfileResolution.resolve(
                cliProfiles: request.inputs.profiles,
                environment: request.inputs.environment
            ).activeProfiles,
            tearsDownAll: downProfile.tearsDownAll
        )
        let (containers, orphanNames) = try mergeOrphansIfNeeded(
            selected: selected,
            discovered: discovered,
            context: context,
            policy: request.orphanPolicy
        )
        return ShutdownContext(
            machineContext: machineContext,
            labelContext: context,
            discovered: discovered,
            containers: containers,
            orphanNames: orphanNames
        )
    }

    package static func executeShutdown(
        request: ProjectDownRequest,
        shutdown: ShutdownContext,
        execution: ProjectDownExecution
    ) async throws {
        let useOrderedShutdown = shutdown.labelContext.fileURLs != nil
        let volumePurgeContext = DownShutdown.volumePurgeContext(
            context: shutdown.labelContext,
            discovered: shutdown.discovered,
            teardownContainers: shutdown.containers
        )
        let wavePolicy = WaveExecutionPolicy(maxConcurrent: request.maxConcurrent)
        try await DownShutdown.tearDownContainers(
            context: shutdown.labelContext,
            containers: shutdown.containers,
            useOrderedShutdown: useOrderedShutdown,
            progress: execution.progress,
            execution: wavePolicy,
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

    private static func mergeOrphansIfNeeded(
        selected: [DiscoveredContainer],
        discovered: [DiscoveredContainer],
        context: ProjectOptions.LabelCommandContext,
        policy: ProjectDownOrphanPolicy?
    ) throws -> ([DiscoveredContainer], Set<String>) {
        guard let policy else {
            if let composeFile = context.composeFile {
                DownShutdown.warnUnmappedContainers(in: selected, composeFile: composeFile)
            }
            return (selected, [])
        }
        guard let composeFile = context.composeFile else {
            WorkspaceHygieneOutput.warnOrphanRemovalSkipped("compose file required")
            return (selected, [])
        }
        let orphans = OrphanRemoval.orphans(
            in: discovered,
            composeFile: composeFile,
            policy: OrphanRemoval.Policy.duringDown(
                profileFilterRequested: policy.profileFilterRequested,
                tearsDownAll: policy.tearsDownAll,
                activeProfiles: policy.activeProfiles
            )
        )
        let merged = OrphanRemoval.mergingContainers(selected, with: orphans)
        return (merged, Set(orphans.map(\.name)))
    }
}
