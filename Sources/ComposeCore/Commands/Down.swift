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
        let request = try downRequest(dryRun: dryRunOptions.isEnabled)
        let shutdown = try await ProjectDownRun.resolveShutdown(request: request)

        if dryRunOptions.isEnabled {
            try await runDryRun(
                context: shutdown.labelContext,
                discovered: shutdown.discovered,
                containers: shutdown.containers,
                orphanNames: shutdown.orphanNames,
                machineContext: shutdown.machineContext
            )
            return
        }

        try await executeShutdown(request: request, shutdown: shutdown)
    }

    private func downRequest(dryRun: Bool) throws -> ProjectDownRequest {
        ProjectDownRequest(
            inputs: projectOptions.composeCommandInputs(
                profiles: profileOptions.profiles,
                machineName: machineOptions.resolvedMachineName
            ),
            dryRun: dryRun,
            removeVolumes: volumes,
            trim: trim,
            maxConcurrent: parallelOptions.resolvedMaxConcurrent(),
            orphanPolicy: workspaceHygiene.shouldRemoveOrphans
                ? ProjectDownOrphanPolicy(
                    profileFilterRequested: profileOptions.profileFilterRequested,
                    tearsDownAll: profileOptions.tearsDownAll,
                    activeProfiles: profileOptions.activeProfileSet
                )
                : nil
        )
    }

    private func executeShutdown(
        request: ProjectDownRequest,
        shutdown: ProjectDownRun.ShutdownContext
    ) async throws {
        let displayNames = Dictionary(
            shutdown.containers.map {
                ($0.name, progressServiceLabel(containerName: $0.name, serviceName: $0.serviceName))
            },
            uniquingKeysWith: { _, last in last }
        )
        let orchestration = makeProgressOrchestration(
            display: progressOptions.resolvedDisplay(),
            phase: .stopping,
            label: { displayNames[$0] ?? $0 }
        )
        try await runOrchestrationCommand(
            lines: orchestration.lines,
            interruptedMessage: "Shutdown interrupted. Some containers may still be running."
        ) {
            try await ProjectDownRun.executeShutdown(
                request: request,
                shutdown: shutdown,
                execution: ProjectDownExecution(progress: orchestration.handlers)
            )
        }
    }
}
