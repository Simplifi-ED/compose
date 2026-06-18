import ArgumentParser
import Foundation

public struct Ps: AsyncParsableCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        abstract: "List containers for the compose project."
    )

    @OptionGroup
    var projectOptions: ProjectOptions

    @OptionGroup
    var profileOptions: ProfileOptions

    @OptionGroup
    var machineOptions: MachineOptions

    @OptionGroup
    var clockSyncOptions: ClockSyncOptions

    @Argument(help: "Limit output to these service names.")
    var services: [String] = []

    public func run() async throws {
        try await ComposeCommandClockSync.execute(cliNoClockSync: clockSyncOptions.isDisabled) {
            guard let machineContext = try await machineOptions
                .resolveContext(stopped: .gracefulExit)
                .machineContextIfReady
            else { return }

            let result = try await ProjectListRun.run(
                ProjectListRequest(
                    inputs: projectOptions.composeCommandInputs(
                        profiles: profileOptions.profiles,
                        machineName: machineContext.machineName,
                        services: services
                    )
                )
            )
            for warning in result.warnings {
                fputs("warning: \(warning)\n", stderr)
            }
            let mode = TerminalMode.resolve()
            let table = ProjectStatus.defaultTable()
            print(table.formatHeader(mode: mode))
            for row in result.rows {
                print(table.formatRow(row.cells))
            }
        }
    }
}
