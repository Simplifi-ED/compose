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
    var osLogOptions: OsLogOptions

    @OptionGroup
    var machineOptions: MachineOptions

    @OptionGroup
    var hostDNSOptions: HostDNSOptions

    @Flag(
        name: .long,
        help: "After startup, follow service logs in the foreground until services exit or you interrupt."
    )
    var attach = false

    public func run() async throws {
        OsLogConfiguration.apply(
            cliNoOslog: osLogOptions.isDisabled,
            dryRun: dryRunOptions.isEnabled
        )
        try parallelOptions.validate()
        try hostDNSOptions.validateMachineCompatibility(machineName: machineOptions.resolvedMachineName)
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
                    fileURLs: startup.fileURLs,
                    machineContext: machineContext,
                    installHostDNS: hostDNSOptions.isEnabled
                )
            )
            return
        }

        let bootedContext = try await machineContext.ensureBooted()
        try await runLive(
            LiveInput(
                plan: startup,
                machineContext: bootedContext,
                installHostDNS: hostDNSOptions.isEnabled
            )
        )
    }
}
