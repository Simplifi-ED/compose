import ArgumentParser
import Foundation

public struct Scale: AsyncParsableCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        abstract: "Reconcile running replica counts without recreating healthy containers."
    )

    @OptionGroup
    var projectOptions: ProjectOptions

    @OptionGroup
    var scaleOptions: ScaleOptions

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

    public func validate() throws {
        try parallelOptions.validate()
        try machineOptions.validateMachineName()
        let overrides = try scaleOptions.resolvedScaleOverrides()
        guard !overrides.isEmpty else {
            throw ComposeError.scaleRequiresTargets
        }
    }

    public func run() async throws {
        try await ComposeCommandClockSync.execute(
            cliNoClockSync: clockSyncOptions.isDisabled,
            dryRun: dryRunOptions.isEnabled,
            cliNoOslog: osLogOptions.isDisabled
        ) {
            let scaleOverrides = try scaleOptions.resolvedScaleOverrides()
            let request = ProjectScaleRequest(
                inputs: projectOptions.composeCommandInputs(
                    profiles: profileOptions.profiles,
                    machineName: machineOptions.resolvedMachineName
                ),
                dryRun: dryRunOptions.isEnabled,
                maxConcurrent: parallelOptions.resolvedMaxConcurrent(),
                scaleOverrides: scaleOverrides
            )
            _ = try await ProjectScaleRun.run(request)
        }
    }
}
