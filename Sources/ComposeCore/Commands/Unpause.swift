import ArgumentParser
import Foundation

public struct Unpause: AsyncParsableCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        abstract: "Resume paused project containers."
    )

    @OptionGroup
    var projectOptions: ProjectOptions

    @OptionGroup
    var profileOptions: ProfileOptions

    @OptionGroup
    var parallelOptions: ParallelOptions

    @OptionGroup
    var dryRunOptions: DryRunOptions

    @OptionGroup
    var osLogOptions: OsLogOptions

    @OptionGroup
    var machineOptions: MachineOptions

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
            profiles: profileOptions.profiles,
            machineContext: machineContext
        )
        try await ProjectPauseRun.run(
            ProjectPauseRequest(
                operation: .unpause,
                scope: ProjectPauseScope(
                    context: context,
                    profileFilterRequested: profileOptions.profileFilterRequested,
                    activeProfiles: profileOptions.activeProfileSet,
                    tearsDownAll: profileOptions.tearsDownAll
                ),
                execution: WaveExecutionPolicy(maxConcurrent: parallelOptions.resolvedMaxConcurrent()),
                dryRunEnabled: dryRunOptions.isEnabled,
                machineContext: machineContext
            )
        )
    }
}
