import ArgumentParser
import Foundation

public struct Events: AsyncParsableCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        abstract: """
        Report container lifecycle events for the project. Without --follow, prints one snapshot \
        of currently running containers. With --follow, polls in the foreground (default 1.5s). \
        Containers that start and stop in under ~1 second may not emit events.
        """
    )

    @OptionGroup
    var projectOptions: ProjectOptions

    @OptionGroup
    var profileOptions: ProfileOptions

    @OptionGroup
    var machineOptions: MachineOptions

    @OptionGroup
    var osLogOptions: OsLogOptions

    @Flag(name: .long, help: "Keep streaming events until interrupted.")
    var follow = false

    @Option(
        name: .long,
        help: "When following, exit after SECONDS if no project containers have appeared."
    )
    var timeout: Int?

    @Argument(help: "Limit output to these service names.")
    var services: [String] = []

    public func validate() throws {
        if let timeout, timeout <= 0 {
            throw ValidationError("--timeout must be a positive integer.")
        }
        if timeout != nil, !follow {
            throw ValidationError("--timeout requires --follow.")
        }
    }

    public func run() async throws {
        OsLogConfiguration.apply(cliNoOslog: osLogOptions.isDisabled)
        guard let machineContext = try await machineOptions
            .resolveContext(stopped: .gracefulExit)
            .machineContextIfReady
        else { return }
        let context = try projectOptions.resolvedLabelCommandContext(
            skipComposeFileOnExplicitProject: true,
            profileFilterRequested: profileOptions.profileFilterRequested,
            machineContext: machineContext
        )
        let filter = try projectOptions.resolvedQueryServiceFilter(
            context: context,
            profileOptions: profileOptions,
            positionalServices: services
        )
        if let filter, filter.isEmpty {
            return
        }

        let timeoutDuration = timeout.map { Duration.seconds($0) }
        let options = ProjectEventsOptions(
            projectName: context.projectName,
            serviceFilter: filter,
            machineContext: machineContext,
            follow: follow,
            timeout: timeoutDuration
        )

        if follow {
            _ = try await ProjectEventsSession.runUntilCancelled(
                options: options,
                policy: .cancelOnly,
                onQuietCancel: {
                    fputs("Events stream ended.\n", stderr)
                }
            )
        } else {
            try await ProjectEventsSession.run(options: options)
        }
    }
}
