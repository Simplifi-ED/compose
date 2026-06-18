import ArgumentParser
import Foundation

public struct Pause: AsyncParsableCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        abstract: "Suspend all running project containers without removing them."
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
    var clockSyncOptions: ClockSyncOptions

    @OptionGroup
    var machineOptions: MachineOptions

    public func run() async throws {
        try await ComposeCommandClockSync.execute(
            cliNoClockSync: clockSyncOptions.isDisabled,
            dryRun: dryRunOptions.isEnabled,
            cliNoOslog: osLogOptions.isDisabled
        ) {
            try parallelOptions.validate()
            guard let machineContext = try await machineOptions
                .resolveContext(stopped: .gracefulExit)
                .machineContextIfReady
            else { return }
            let context = try projectOptions.resolvedLabelCommandContext(
                profileFilterRequested: profileOptions.profileFilterRequested,
                profiles: profileOptions.profiles,
                machineContext: machineContext
            )
            try await ProjectPauseRun.run(
                ProjectPauseRequest(
                    operation: .pause,
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
}
