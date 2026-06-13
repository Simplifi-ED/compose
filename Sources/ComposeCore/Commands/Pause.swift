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
    var machineOptions: MachineOptions

    public func run() async throws {
        try parallelOptions.validate()
        var machineContext = try await machineOptions.resolveContext().machineContext
        if machineContext.isMachineMode, !dryRunOptions.isEnabled, !machineContext.isMachineRunning {
            machineContext = try await machineContext.ensureBooted()
        }
        let context = try projectOptions.resolvedLabelCommandContext(
            profileFilterRequested: profileOptions.profileFilterRequested,
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
