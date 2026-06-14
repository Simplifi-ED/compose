import ContainerAPIClient
import ContainerCommands
import ContainerResource
import Foundation

extension ComposeContainerGateway {
    package static func copyIn(
        id: String,
        source: String,
        destination: String,
        mode: UInt32,
        createParents: Bool,
        machineContext: MachineContext = .applicationSandbox
    ) async throws {
        if machineContext.isMachineMode {
            throw ComposeError.machineUnsupportedOperation("copy in")
        }
        try await ContainerClient().copyIn(
            id: id,
            source: source,
            destination: destination,
            mode: mode,
            createParents: createParents
        )
    }

    package static func copyOut(
        id: String,
        source: String,
        destination: String,
        createParents: Bool,
        machineContext: MachineContext = .applicationSandbox
    ) async throws {
        if machineContext.isMachineMode {
            throw ComposeError.machineUnsupportedOperation("copy out")
        }
        try await ContainerClient().copyOut(
            id: id,
            source: source,
            destination: destination,
            createParents: createParents
        )
    }

    package static func createProcess(
        containerId: String,
        processId: String,
        configuration: ProcessConfiguration,
        stdio: [FileHandle?],
        machineContext: MachineContext = .applicationSandbox
    ) async throws -> any ClientProcess {
        if machineContext.isMachineMode {
            throw ComposeError.machineUnsupportedOperation("exec")
        }
        return try await ContainerClient().createProcess(
            containerId: containerId,
            processId: processId,
            configuration: configuration,
            stdio: stdio
        )
    }

    package static func logs(
        id: String,
        machineContext: MachineContext = .applicationSandbox
    ) async throws -> [FileHandle] {
        if machineContext.isMachineMode {
            throw ComposeError.machineUnsupportedOperation("logs streaming")
        }
        return try await ContainerClient().logs(id: id)
    }

    /// Native engine event stream hook. Empty until upstream exposes `containerEvent` XPC handling.
    package static func events(
        machineContext: MachineContext = .applicationSandbox
    ) -> AsyncStream<ProjectEvent> {
        _ = machineContext
        return AsyncStream { continuation in
            continuation.finish()
        }
    }
}
