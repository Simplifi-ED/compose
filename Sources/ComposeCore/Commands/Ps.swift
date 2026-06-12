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

    @Argument(help: "Limit output to these service names.")
    var services: [String] = []

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
        let rows = ProjectStatus.rows(from: containers, filter: filter)
        let mode = TerminalMode.resolve()
        let table = ProjectStatus.defaultTable()
        print(table.formatHeader(mode: mode))
        for row in rows {
            print(table.formatRow(row.cells))
        }
    }
}
