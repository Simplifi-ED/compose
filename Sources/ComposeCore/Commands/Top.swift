import ArgumentParser
import Foundation

public struct Top: AsyncParsableCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        abstract: "Display live resource usage for project services."
    )

    @OptionGroup
    var projectOptions: ProjectOptions

    @Argument(help: "Limit output to these service names.")
    var services: [String] = []

    public func run() async throws {
        let context = try projectOptions.resolvedLabelCommandContext(
            skipComposeFileOnExplicitProject: true
        )
        let containers = try await ContainerDiscovery.projectContainers(forProject: context.projectName)
        let filter = services.isEmpty ? nil : Set(services)
        let targets = ProjectStatus.filteredContainers(from: containers, filter: filter)

        let mode = TerminalMode.resolve()
        let table = ProjectStats.defaultStatsTable()

        if targets.isEmpty {
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
