import ArgumentParser
import Foundation

public struct Watch: AsyncParsableCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        abstract: """
        Watch local paths and sync changes into running containers (requires compose up first).
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

    @OptionGroup
    var clockSyncOptions: ClockSyncOptions

    @Argument(help: "Limit watching to these service names.")
    var services: [String] = []

    public func run() async throws {
        try await ComposeCommandClockSync.execute(cliNoClockSync: clockSyncOptions.isDisabled) {
            OsLogConfiguration.apply(cliNoOslog: osLogOptions.isDisabled)
            try machineOptions.rejectIfUnsupported(commandName: "watch")
            let fileURLs = try projectOptions.resolvedFileURLs()
            let composeFile = try ComposeParser.parse(fileURLs: fileURLs)
            let projectName = try projectOptions.resolvedProjectName(
                composeFile: composeFile,
                fileURL: fileURLs[0]
            )
            let composeDirectory = fileURLs[0].deletingLastPathComponent()

            let serviceFilter: Set<String>? = services.isEmpty ? nil : Set(services)
            let containers = try await ContainerDiscovery.projectContainers(forProject: projectName)
            let configuration = try WatchSession.buildConfiguration(
                context: WatchSession.BuildContext(
                    composeFile: composeFile,
                    projectName: projectName,
                    composeDirectory: composeDirectory,
                    activeProfiles: profileOptions.activeProfileSet,
                    serviceFilter: serviceFilter,
                    containers: containers
                )
            )

            let watchedNames = configuration.services.map(\.serviceName).joined(separator: ", ")
            fputs("Watching \(watchedNames). Press Ctrl+C to stop.\n", stderr)

            _ = try await SignalForwarding.runUntilCancelled(policy: .cancelOnly) {
                try await WatchSession.run(
                    configuration: configuration,
                    dependencies: WatchSession.Dependencies(projectName: projectName)
                )
            }
        }
    }
}
