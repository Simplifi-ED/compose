import ArgumentParser
import Foundation

public struct Top: AsyncParsableCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        abstract: "Display live resource usage for project services.",
        aliases: ["stats"]
    )

    @OptionGroup
    var projectOptions: ProjectOptions

    @OptionGroup
    var profileOptions: ProfileOptions

    @OptionGroup
    var machineOptions: MachineOptions

    @OptionGroup
    var osLogOptions: OsLogOptions

    @OptionGroup
    var clockSyncOptions: ClockSyncOptions

    @Option(
        name: .long,
        help: "Seconds between live refreshes (minimum 1). Default: 2."
    )
    var interval: Int = ProjectStats.defaultSampleIntervalSeconds

    @Argument(help: "Limit output to these service names.")
    var services: [String] = []

    public func validate() throws {
        try Self.validateInterval(interval)
    }

    public func run() async throws {
        try await ComposeCommandClockSync.execute(cliNoClockSync: clockSyncOptions.isDisabled) {
            OsLogConfiguration.apply(cliNoOslog: osLogOptions.isDisabled)
            try machineOptions.rejectIfUnsupported(commandName: "top/stats")
            let context = try projectOptions.resolvedLabelCommandContext(
                skipComposeFileOnExplicitProject: true,
                profileFilterRequested: profileOptions.profileFilterRequested,
                profiles: profileOptions.profiles
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

            let sampleInterval = Duration.seconds(interval)
            _ = try await StatsStreamSession.runUntilCancelled(
                projectName: context.projectName,
                serviceFilter: filter,
                mode: mode,
                sampleInterval: sampleInterval,
                policy: .cancelOnly,
                onQuietCancel: {
                    fputs("Stats stream ended.\n", stderr)
                }
            )
        }
    }

    package static func validateInterval(_ seconds: Int) throws {
        if seconds < 1 {
            throw ValidationError("--interval must be at least 1 second.")
        }
    }

    package var parsedInterval: Int { interval }
}
