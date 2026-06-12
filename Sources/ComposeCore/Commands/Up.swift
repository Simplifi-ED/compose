import ArgumentParser
import Foundation

public struct Up: AsyncParsableCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        abstract: "Create and start containers defined in the compose file."
    )

    @OptionGroup
    var projectOptions: ProjectOptions

    @OptionGroup
    var progressOptions: ProgressOptions

    @OptionGroup
    var shutdownTimeoutOptions: ShutdownTimeoutOptions

    @OptionGroup
    var profileOptions: ProfileOptions

    @OptionGroup
    var scaleOptions: ScaleOptions

    @OptionGroup
    var parallelOptions: ParallelOptions

    @OptionGroup
    var workspaceHygiene: WorkspaceHygieneOptions

    @OptionGroup
    var dryRunOptions: DryRunOptions

    @OptionGroup
    var machineOptions: MachineOptions

    @Flag(
        name: .long,
        help: "After startup, follow service logs in the foreground until services exit or you interrupt."
    )
    var attach = false

    public func run() async throws {
        try parallelOptions.validate()
        let machineContext = try await machineOptions.resolveContext().machineContext
        let startup = try resolveStartupPlan(machineName: machineOptions.resolvedMachineName)

        if dryRunOptions.isEnabled {
            try await runDryRun(
                DryRunInput(
                    projectName: startup.projectName,
                    composeFile: startup.composeFile,
                    layers: startup.layers,
                    healthContext: startup.healthContext,
                    buildPlans: startup.buildPlans,
                    networkPlans: startup.networkPlans,
                    volumePlans: startup.volumePlans,
                    machineContext: machineContext
                )
            )
            return
        }

        let bootedContext = try await machineContext.ensureBooted()
        try await runLive(
            LiveInput(
                buildPlans: startup.buildPlans,
                networkPlans: startup.networkPlans,
                volumePlans: startup.volumePlans,
                projectName: startup.projectName,
                composeFile: startup.composeFile,
                fileURLs: startup.fileURLs,
                layers: startup.layers,
                plans: startup.plans,
                healthContext: startup.healthContext,
                machineContext: bootedContext
            )
        )
    }
}
