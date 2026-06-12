import ArgumentParser
import Darwin
import Foundation

public struct Exec: AsyncParsableCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        abstract: "Run a command in a running service container."
    )

    @OptionGroup
    var projectOptions: ProjectOptions

    @OptionGroup
    var dryRunOptions: DryRunOptions

    @Flag(name: .short, help: "Keep STDIN open even if not attached.")
    var interactive = false

    @Flag(name: .short, help: "Allocate a pseudo-TTY.")
    var tty = false

    @Option(
        name: .long,
        help: "Seconds to wait after SIGTERM before SIGKILL when stopping containers on interrupt."
    )
    var timeout: Int32 = GracefulStopOptions.defaultGraceSeconds

    @Argument(help: "Service name.")
    var service: String

    @Argument(parsing: .captureForPassthrough, help: "Command and arguments to run in the container.")
    var command: [String] = []

    public func validate() throws {
        if command.isEmpty {
            throw ValidationError("exec requires a command.")
        }
        try ShutdownTimeoutOptions.validateTimeout(timeout)
    }

    public func run() async throws {
        let context = try projectOptions.resolvedLabelCommandContext(
            skipComposeFileOnExplicitProject: true
        )
        let containers = try await ContainerDiscovery.projectContainers(forProject: context.projectName)
        let target = try ExecContainerResolver.resolve(
            projectName: context.projectName,
            serviceName: service,
            containers: containers
        )

        if dryRunOptions.isEnabled {
            let manifest = DryRunManifest()
            await manifest.recordExec(container: target.name, command: command)
            await manifest.printLines()
            return
        }

        let ioFlags = ExecSession.IOFlags.resolve(
            explicitInteractive: interactive,
            explicitTTY: tty,
            stdinIsTTY: isatty(STDIN_FILENO) == 1
        )

        let shutdownContext = ProjectShutdownContext(
            projectName: context.projectName,
            composeFile: context.composeFile,
            fileURLs: context.fileURLs,
            options: GracefulStopOptions(graceSeconds: timeout)
        )

        let executable = command[0]
        let arguments = Array(command.dropFirst())

        try await ExecSession.run(
            configuration: ExecSession.Configuration(
                containerName: target.name,
                projectName: context.projectName,
                serviceName: service,
                executable: executable,
                arguments: arguments,
                processTerminal: ioFlags.processTerminal,
                interactive: ioFlags.interactive,
                useInteractivePTY: ioFlags.useInteractivePTY
            ),
            shutdownContext: shutdownContext
        )
    }
}
