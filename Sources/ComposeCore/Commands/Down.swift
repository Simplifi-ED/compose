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
        let fileURL = projectOptions.resolvedFileURLIfPresent()
        let projectName = try projectOptions.resolvedProjectName(fileURL: fileURL)
        let containers = try await ContainerDiscovery.containers(forProject: projectName)

        if let fileURL {
            let composeFile = try ComposeParser.parse(fileURL: fileURL)
            let layers = try ServicePlanner.shutdownContainerLayers(
                for: composeFile,
                containers: containers
            )
            let knownServices = Set(composeFile.services.keys)
            let unmappedContainers = containers.filter { container in
                guard let serviceName = container.serviceName else { return true }
                return !knownServices.contains(serviceName)
            }
            if !unmappedContainers.isEmpty {
                let names = unmappedContainers.map(\.name).joined(separator: ", ")
                fputs(
                    "Warning: \(unmappedContainers.count) container(s) without a compose service mapping (\(names)) stop last; depends_on order may not apply to them.\n",
                    stderr
                )
            }
            try await ServiceRunner.down(layers: layers)
        } else {
            try await ServiceRunner.down(containers: containers)
        }

        for container in containers {
            print(container.name)
        }
    }
}
