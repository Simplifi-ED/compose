import ContainerAPIClient
import ContainerResource
import ContainerizationError
import Foundation

/// Polls container runtime status until every watched container has stopped.
package enum ContainerExitWatch {
    package typealias StatusProvider = @Sendable (String) async throws -> RuntimeStatus?

    package static func waitUntilAllStopped(
        ids: [String],
        pollInterval: Duration = .milliseconds(250),
        status: StatusProvider = defaultStatus
    ) async throws {
        guard !ids.isEmpty else { return }

        var pending = Set(ids)
        while !pending.isEmpty {
            try Task.checkCancellation()

            var stillRunning: Set<String> = []
            for id in pending {
                switch try await status(id) {
                case .stopped, nil:
                    continue
                case .running, .stopping, .unknown:
                    stillRunning.insert(id)
                }
            }
            pending = stillRunning

            if !pending.isEmpty {
                try await Task.sleep(for: pollInterval)
            }
        }
    }

    package static func statusProvider(
        machineContext: MachineContext = .applicationSandbox
    ) -> StatusProvider {
        { id in
            do {
                return try await ComposeContainerGateway.get(
                    id: id,
                    machineContext: machineContext
                ).status
            } catch {
                if ContainerTeardown.isIgnorableError(error) {
                    return nil
                }
                throw error
            }
        }
    }

    private static func defaultStatus(id: String) async throws -> RuntimeStatus? {
        try await statusProvider()(id)
    }
}
