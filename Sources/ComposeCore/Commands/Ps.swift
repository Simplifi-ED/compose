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

    @Argument(help: "Limit output to these service names.")
    var services: [String] = []

    public func run() async throws {
        let context = try projectOptions.resolvedLabelCommandContext(
            skipComposeFileOnExplicitProject: true,
            profileFilterRequested: profileOptions.profileFilterRequested
        )
        let containers = try await ContainerDiscovery.projectContainers(forProject: context.projectName)
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
