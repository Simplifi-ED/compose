import ArgumentParser
import Darwin
import Foundation

public struct Run: AsyncParsableCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        abstract: "Run a one-off command in a new container from a service definition."
    )

    @OptionGroup
    var projectOptions: ProjectOptions

    @OptionGroup
    var progressOptions: ProgressOptions

    @OptionGroup
    var dryRunOptions: DryRunOptions

    @OptionGroup
    var osLogOptions: OsLogOptions

    @OptionGroup
    var machineOptions: MachineOptions

    @Flag(name: .long, help: "Remove the container after it exits.")
    var remove = false

    @Flag(name: .short, help: "Keep STDIN open even if not attached.")
    var interactive = false

    @Flag(name: .short, help: "Allocate a pseudo-TTY.")
    var tty = false

    @Option(
        name: .long,
        help: "Seconds to wait after SIGTERM before SIGKILL when stopping the run container on interrupt."
    )
    var timeout: Int32 = GracefulStopOptions.defaultGraceSeconds

    @Argument(help: "Service name.")
    var service: String

    @Argument(parsing: .captureForPassthrough, help: "Command and arguments. Uses the service command when omitted.")
    var command: [String] = []

    public func validate() throws {
        try ShutdownTimeoutOptions.validateTimeout(timeout)
    }

    public func run() async throws {
        OsLogConfiguration.apply(
            cliNoOslog: osLogOptions.isDisabled,
            dryRun: dryRunOptions.isEnabled
        )
        try machineOptions.rejectIfUnsupported(commandName: "run")
        let resolved = try resolveRun()

        if dryRunOptions.isEnabled {
            try await runDryRun(
                buildPlans: resolved.buildPlans,
                networkPlans: resolved.networkPlans,
                volumePlans: resolved.volumePlans,
                plan: resolved.plan
            )
            return
        }

        try await prepareRunResources(
            buildPlans: resolved.buildPlans,
            networkPlans: resolved.networkPlans,
            volumePlans: resolved.volumePlans,
            projectName: resolved.projectName
        )

        try await RunSession.run(
            plan: resolved.plan,
            shutdownContext: RunShutdownContext(
                containerID: resolved.plan.name,
                projectName: resolved.projectName,
                options: GracefulStopOptions(graceSeconds: timeout)
            ),
            useInteractivePTY: resolvedIOFlags().useInteractivePTY
        )
    }

    private func resolvedIOFlags() -> InteractiveSession.IOFlags {
        InteractiveSession.IOFlags.resolve(
            explicitInteractive: interactive,
            explicitTTY: tty,
            stdinIsTTY: isatty(STDIN_FILENO) == 1
        )
    }

    func makeRunPlan(
        composeFile: ComposeFile,
        projectName: String,
        serviceDirectory: URL,
        composeService: ComposeService
    ) throws -> ServicePlan {
        let ioFlags = resolvedIOFlags()
        let suffix = dryRunOptions.isEnabled
            ? "dryrun"
            : String(UUID().uuidString.lowercased().prefix(8))
        return try ServicePlanner.runPlan(
            context: ServicePlanner.PlanningContext(
                composeFile: composeFile,
                projectName: projectName,
                composeDirectory: serviceDirectory
            ),
            serviceName: service,
            service: composeService,
            options: RunPlanOptions(
                removeContainer: remove,
                commandOverride: command.isEmpty ? nil : command,
                interactive: ioFlags.interactive,
                processTerminal: ioFlags.processTerminal,
                nameSuffix: String(suffix)
            )
        )
    }

    private func runDryRun(
        buildPlans: [BuildRunner.Plan],
        networkPlans: [NetworkPlanning.Plan],
        volumePlans: [VolumePlanning.Plan],
        plan: ServicePlan
    ) async throws {
        let manifest = DryRunManifest()
        if !buildPlans.isEmpty {
            try await BuildRunner.buildAll(
                buildPlans,
                progress: nil,
                dryRunManifest: manifest
            )
        }
        try await NetworkRunner.createAll(
            networkPlans,
            projectName: plan.projectName,
            dryRunManifest: manifest
        )
        try await VolumeRunner.createAll(
            volumePlans,
            projectName: plan.projectName,
            dryRunManifest: manifest
        )
        await manifest.recordCreate(plan)
        await manifest.printLines()
    }
}
