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
        let ioFlags = InteractiveSession.IOFlags.resolve(
            explicitInteractive: interactive,
            explicitTTY: tty,
            stdinIsTTY: isatty(STDIN_FILENO) == 1
        )
        let suffix = UUID().uuidString.lowercased().prefix(8)
        let plan = try ServicePlanner.runPlan(
            context: ServicePlanner.PlanningContext(
                composeFile: composeFile,
                projectName: projectName,
                composeDirectory: composeService.projectDirectory(orDefault: composeDirectory)
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

        let shutdownContext = RunShutdownContext(
            containerID: plan.name,
            projectName: projectName,
            options: GracefulStopOptions(graceSeconds: timeout)
        )

        try await RunSession.run(
            plan: plan,
            shutdownContext: shutdownContext,
            useInteractivePTY: ioFlags.useInteractivePTY
        )
    }
}
