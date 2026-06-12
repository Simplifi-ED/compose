import Foundation

extension ServiceRunner {
    /// SIGTERM each container with grace, then SIGKILL. Collects per-container failures.
    package static func stopGracefully(
        layers: [[DiscoveredContainer]],
        options: GracefulStopOptions,
        machineContext: MachineContext = .applicationSandbox
    ) async throws -> [(name: String, error: Error)] {
        try await runContainerWaves(
            layers: layers,
            progress: nil,
            failFast: false
        ) { container in
            try await ContainerTeardown.stopGracefully(
                id: container.name,
                options: options,
                machineContext: machineContext
            )
        } onWaveComplete: { _ in }
    }
}
