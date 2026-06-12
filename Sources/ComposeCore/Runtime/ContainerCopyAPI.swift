import ContainerAPIClient
import ContainerResource
import Foundation

/// Shared `ContainerClient` copy/get entry points for watch sync and compose cp.
package enum ContainerCopyAPI {
    package typealias CopyIn = @Sendable (String, String, String, UInt32, Bool) async throws -> Void
    package typealias CopyOut = @Sendable (String, String, String, Bool) async throws -> Void
    package typealias GetContainer = @Sendable (String) async throws -> ContainerSnapshot

    package static func copyIn(
        id: String,
        source: String,
        destination: String,
        mode: UInt32,
        createParents: Bool,
        machineContext: MachineContext = .applicationSandbox
    ) async throws {
        if machineContext.isMachineMode {
            let snapshot = try machineContext.requireSnapshot()
            var args = ["cp"]
            if createParents {
                args.append("--parents")
            }
            args.append(contentsOf: [source, "\(id):\(destination)"])
            try await MachineInVMRunner.run(snapshot: snapshot, containerArguments: args)
            return
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
            let snapshot = try machineContext.requireSnapshot()
            var args = ["cp"]
            if createParents {
                args.append("--parents")
            }
            args.append(contentsOf: ["\(id):\(source)", destination])
            try await MachineInVMRunner.run(snapshot: snapshot, containerArguments: args)
            return
        }
        try await ContainerClient().copyOut(
            id: id,
            source: source,
            destination: destination,
            createParents: createParents
        )
    }

    package static func get(
        id: String,
        machineContext: MachineContext = .applicationSandbox
    ) async throws -> ContainerSnapshot {
        try await ComposeContainerGateway.get(id: id, machineContext: machineContext)
    }
}
