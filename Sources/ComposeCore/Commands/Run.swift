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
        let fileURLs = try projectOptions.resolvedFileURLs()
        let composeFile = try ComposeParser.parse(fileURLs: fileURLs)
        let projectName = try projectOptions.resolvedProjectName(
            composeFile: composeFile,
            fileURL: fileURLs[0]
        )
        guard let composeService = composeFile.services[service] else {
            throw ComposeError.undefinedService(service: service)
        }

        let composeDirectory = fileURLs[0].deletingLastPathComponent()
        let serviceDirectory = composeService.projectDirectory(orDefault: composeDirectory)
        let buildPlans = try BuildRunner.runBuildPlans(
            targetServiceName: service,
            composeFile: composeFile,
            projectName: projectName,
            composeDirectory: composeDirectory
        )

        let plan = try makeRunPlan(
            composeFile: composeFile,
            projectName: projectName,
            serviceDirectory: serviceDirectory,
            composeService: composeService
        )

        if dryRunOptions.isEnabled {
            try await runDryRun(buildPlans: buildPlans, plan: plan)
            return
        }

        if !buildPlans.isEmpty {
            try await BuildRunner.buildAll(
                buildPlans,
                progress: progressOptions.progress,
                dryRunManifest: nil
            )
        }

        try await RunSession.run(
            plan: plan,
            shutdownContext: RunShutdownContext(
                containerID: plan.name,
                projectName: projectName,
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

    private func makeRunPlan(
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

    private func runDryRun(buildPlans: [BuildRunner.Plan], plan: ServicePlan) async throws {
        let manifest = DryRunManifest()
        if !buildPlans.isEmpty {
            try await BuildRunner.buildAll(
                buildPlans,
                progress: nil,
                dryRunManifest: manifest
            )
        }
        await manifest.recordCreate(plan)
        await manifest.printLines()
    }
}
