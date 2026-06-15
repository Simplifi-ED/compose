import ArgumentParser
import Foundation

public struct Down: AsyncParsableCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        abstract: "Stop and remove containers for the compose project."
    )

    @OptionGroup
    var projectOptions: ProjectOptions

    @OptionGroup
    var progressOptions: ProgressOptions

    @OptionGroup
    var profileOptions: ProfileOptions

    @OptionGroup
    var parallelOptions: ParallelOptions

    @OptionGroup
    var workspaceHygiene: WorkspaceHygieneOptions

    @OptionGroup
    var dryRunOptions: DryRunOptions

    @OptionGroup
    var osLogOptions: OsLogOptions

    @OptionGroup
    var machineOptions: MachineOptions

    @Flag(
        name: .shortAndLong,
        help: "Remove project bind-mount directories and named volumes declared in the compose file."
    )
    var volumes = false

    @Flag(
        name: .long,
        help: "Reclaim APFS sparse disk space after teardown (APFS hosts only; guest fstrim)."
    )
    var trim = false

    public func run() async throws {
        OsLogConfiguration.apply(
            cliNoOslog: osLogOptions.isDisabled,
            dryRun: dryRunOptions.isEnabled
        )
        try parallelOptions.validate()
        var machineContext = try await machineOptions.resolveContext().machineContext
        if machineContext.isMachineMode, !dryRunOptions.isEnabled, !machineContext.isMachineRunning {
            machineContext = try await machineContext.ensureBooted()
        }
        let context = try projectOptions.resolvedLabelCommandContext(
            profileFilterRequested: profileOptions.profileFilterRequested,
            machineContext: machineContext
        )
        let discovered = try await ContainerDiscovery.containers(
            forProject: context.projectName,
            machineContext: machineContext
        )
        let containers = try DownShutdown.filteredContainers(
            discovered: discovered,
            context: context,
            profileFilterRequested: profileOptions.profileFilterRequested,
            activeProfiles: profileOptions.activeProfileSet,
            tearsDownAll: profileOptions.tearsDownAll
        )
        let resolution = try resolveContainersForShutdown(
            discovered: discovered,
            selected: containers,
            context: context
        )

        if dryRunOptions.isEnabled {
            try await runDryRun(
                context: context,
                discovered: discovered,
                containers: resolution.containers,
                orphanNames: resolution.orphanNames,
                machineContext: machineContext
            )
            return
        }

        try await executeShutdown(
            context: context,
            discovered: discovered,
            containers: resolution.containers,
            machineContext: machineContext
        )
    }

    private func executeShutdown(
        context: ProjectOptions.LabelCommandContext,
        discovered: [DiscoveredContainer],
        containers: [DiscoveredContainer],
        machineContext: MachineContext
    ) async throws {
        let useOrderedShutdown = context.fileURLs != nil && !projectOptions.hasExplicitProjectName
        let volumePurgeContext = DownShutdown.volumePurgeContext(
            context: context,
            discovered: discovered,
            teardownContainers: containers
        )
        let displayNames = Dictionary(
            containers.map {
                ($0.name, progressServiceLabel(containerName: $0.name, serviceName: $0.serviceName))
            },
            uniquingKeysWith: { _, last in last }
        )
        let orchestration = makeProgressOrchestration(
            display: progressOptions.resolvedDisplay(),
            phase: .stopping,
            label: { displayNames[$0] ?? $0 }
        )

        let shouldPurgeVolumes = volumes
        let shouldTrim = trim
        let execution = WaveExecutionPolicy(maxConcurrent: parallelOptions.resolvedMaxConcurrent())
        try await runOrchestrationCommand(
            lines: orchestration.lines,
            interruptedMessage: "Shutdown interrupted. Some containers may still be running."
        ) {
            try await DownShutdown.tearDownContainers(
                context: context,
                containers: containers,
                useOrderedShutdown: useOrderedShutdown,
                progress: orchestration.handlers,
                execution: execution,
                machineContext: machineContext,
                trimBeforeDelete: shouldTrim
            )
            try await DownShutdown.finishProjectTeardown(
                DownShutdown.FinishTeardownInput(
                    context: context,
                    discovered: discovered,
                    teardownContainers: containers,
                    shouldPurgeVolumes: shouldPurgeVolumes,
                    shouldTrim: shouldTrim,
                    bindPurgeContext: volumePurgeContext,
                    machineContext: machineContext
                )
            )
        }
    }
}
