import ArgumentParser
import Darwin
import Foundation

public struct Logs: AsyncParsableCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        abstract: "View output from project services."
    )

    @OptionGroup
    var projectOptions: ProjectOptions

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
        let context = try projectOptions.resolvedLabelCommandContext(
            skipComposeFileOnExplicitProject: true
        )
        let containers = try await ContainerDiscovery.projectContainers(forProject: context.projectName)
        let sources = makeLogSources(from: containers, services: services)
        guard !sources.isEmpty else { return }

        if follow {
            fflush(stdout)
            setbuf(stdout, nil)
        }

        let mode = TerminalMode.resolve()
        let options = LogStreamOptions(tail: tail, follow: follow, boot: boot, mode: mode)
        try await LogMultiplexer.run(sources: sources, options: options)
    }
}
