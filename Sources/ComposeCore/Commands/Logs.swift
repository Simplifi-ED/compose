import ArgumentParser
import Foundation

public struct Logs: AsyncParsableCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        abstract: "View output from project services."
    )

    @OptionGroup
    var projectOptions: ProjectOptions

    @OptionGroup
    var profileOptions: ProfileOptions

    @OptionGroup
    var machineOptions: MachineOptions

    @Flag(name: .long, help: "Stream new log lines.")
    var follow = false

    @Option(name: .long, help: "Show this many lines from the end of each service log.")
    var tail: Int?

    @Flag(help: "Show boot log instead of container output.")
    var boot = false

    @Argument(help: "Limit output to these service names.")
    var services: [String] = []

    public func validate() throws {
        if let tail, tail <= 0 {
            throw ValidationError("--tail must be a positive integer.")
        }
    }

    public func run() async throws {
        guard let machineContext = try await machineOptions
            .resolveContext(stopped: .gracefulExit)
            .machineContextIfReady
        else { return }
        let context = try projectOptions.resolvedLabelCommandContext(
            skipComposeFileOnExplicitProject: true,
            profileFilterRequested: profileOptions.profileFilterRequested,
            machineContext: machineContext
        )
        let containers = try await ContainerDiscovery.projectContainers(
            forProject: context.projectName,
            machineContext: machineContext
        )
        let filter = try projectOptions.resolvedQueryServiceFilter(
            context: context,
            profileOptions: profileOptions,
            positionalServices: services
        )
        let sources = makeLogSources(from: containers, filter: filter)
        guard !sources.isEmpty else { return }

        let mode = TerminalMode.resolve()
        let options = LogStreamOptions(
            tail: tail,
            follow: follow,
            boot: boot,
            mode: mode,
            machineContext: machineContext
        )

        if follow {
            _ = try await LogFollowSession.runUntilCancelled(
                sources: sources,
                options: options,
                policy: .cancelOnly,
                onQuietCancel: {
                    fputs("Log follow ended.\n", stderr)
                }
            )
        } else {
            try await LogMultiplexer.run(sources: sources, options: options)
        }
    }
}
