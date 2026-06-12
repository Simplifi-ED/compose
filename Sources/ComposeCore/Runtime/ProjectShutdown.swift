import Foundation

/// Resolved project inputs for coordinated container shutdown.
package struct ProjectShutdownContext: Sendable {
    package let projectName: String
    package let composeFile: ComposeFile?
    package let fileURLs: [URL]?
    package let options: GracefulStopOptions
    package let machineContext: MachineContext

    package init(
        projectName: String,
        composeFile: ComposeFile?,
        fileURLs: [URL]?,
        options: GracefulStopOptions,
        machineContext: MachineContext = .applicationSandbox
    ) {
        self.projectName = projectName
        self.composeFile = composeFile
        self.fileURLs = fileURLs
        self.options = options
        self.machineContext = machineContext
    }
}

/// Stops all containers for a compose project with SIGTERM grace, then SIGKILL.
package enum ProjectShutdown {
    package static func stop(context: ProjectShutdownContext) async throws {
        let containers = try await ContainerDiscovery.containers(
            forProject: context.projectName,
            machineContext: context.machineContext
        )
        guard !containers.isEmpty else { return }

        fputs("Stopping project containers…\n", stderr)

        let layers = try ServicePlanner.shutdownLayers(
            for: context.composeFile,
            containers: containers
        )
        let failures = try await ServiceRunner.stopGracefully(
            layers: layers,
            options: context.options,
            machineContext: context.machineContext
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

}
