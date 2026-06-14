import ArgumentParser
import Foundation

public struct Top: AsyncParsableCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        abstract: "Display live resource usage for project services."
    )

    @OptionGroup
    var projectOptions: ProjectOptions

    @OptionGroup
    var profileOptions: ProfileOptions

    @OptionGroup
    var machineOptions: MachineOptions

    @OptionGroup
    var osLogOptions: OsLogOptions

    @Argument(help: "Limit output to these service names.")
    var services: [String] = []

    public func run() async throws {
        OsLogConfiguration.apply(cliNoOslog: osLogOptions.isDisabled)
        try machineOptions.rejectIfUnsupported(commandName: "top")
        let context = try projectOptions.resolvedLabelCommandContext(
            skipComposeFileOnExplicitProject: true,
            profileFilterRequested: profileOptions.profileFilterRequested
        )
        let filter = try projectOptions.resolvedQueryServiceFilter(
            context: context,
            profileOptions: profileOptions,
            positionalServices: services
        )

        let mode = TerminalMode.resolve()
        let table = ProjectStats.defaultStatsTable()

        if let filter, filter.isEmpty {
            print(table.formatHeader(mode: mode))
            return
        }

        _ = try await StatsStreamSession.runUntilCancelled(
            projectName: context.projectName,
            serviceFilter: filter,
            mode: mode,
            policy: .cancelOnly,
            onQuietCancel: {
                fputs("Stats stream ended.\n", stderr)
            }
        )
    }
}
