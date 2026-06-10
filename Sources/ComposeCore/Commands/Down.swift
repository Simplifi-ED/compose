import ArgumentParser
import Foundation

public struct Down: AsyncParsableCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        abstract: "Stop and remove containers for the compose project."
    )

    @OptionGroup
    var projectOptions: ProjectOptions

    public func run() async throws {
        let projectName = try projectOptions.resolvedProjectName()
        let containers = try await ContainerDiscovery.containers(forProject: projectName)

        try await ServiceRunner.down(containers: containers)

        for container in containers {
            print(container.name)
        }
    }
}
