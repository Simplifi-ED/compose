import Foundation

/// Resolved project inputs for coordinated container shutdown.
package struct ProjectShutdownContext: Sendable {
    package let projectName: String
    package let composeFile: ComposeFile?
    package let fileURLs: [URL]?
    package let options: GracefulStopOptions

    package init(
        projectName: String,
        composeFile: ComposeFile?,
        fileURLs: [URL]?,
        options: GracefulStopOptions
    ) {
        self.projectName = projectName
        self.composeFile = composeFile
        self.fileURLs = fileURLs
        self.options = options
    }
}

/// Stops all containers for a compose project with SIGTERM grace, then SIGKILL.
package enum ProjectShutdown {
    package static func stop(context: ProjectShutdownContext) async throws {
        let containers = try await ContainerDiscovery.containers(forProject: context.projectName)
        guard !containers.isEmpty else { return }

        fputs("Stopping project containers…\n", stderr)

        let layers = try shutdownLayers(for: context.composeFile, containers: containers)
        let failures = try await ServiceRunner.stopGracefully(
            layers: layers,
            options: context.options
        )

        for failure in failures {
            fputs(
                "Couldn't stop '\(failure.name)': \(failure.error.localizedDescription).\n",
                stderr
            )
        }

        let stoppedCount = containers.count - failures.count
        if failures.isEmpty {
            fputs("Stopped \(stoppedCount) container\(stoppedCount == 1 ? "" : "s").\n", stderr)
        }
    }

    private static func shutdownLayers(
        for composeFile: ComposeFile?,
        containers: [DiscoveredContainer]
    ) throws -> [[DiscoveredContainer]] {
        guard let composeFile else {
            return [containers]
        }
        return try ServicePlanner.shutdownContainerLayers(for: composeFile, containers: containers)
    }
}
