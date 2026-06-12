import Foundation
import MachineAPIClient

/// Booted, running container machine for in-VM `container` CLI I/O.
///
/// Construct only via ``MachineContext/bootedContext()`` after ``MachineContext/ensureBooted()``
/// on mutating command paths, or when inspect shows a running machine.
package struct BootedMachineContext: Sendable {
    package let machineName: String
    package let snapshot: MachineSnapshot

    fileprivate init(machineName: String, snapshot: MachineSnapshot) {
        precondition(MachineContext.isRunning(snapshot))
        self.machineName = machineName
        self.snapshot = snapshot
    }
}

extension MachineContext {
    /// Running machine snapshot for in-VM I/O. Requires a booted, running machine in machine mode.
    package func bootedContext() throws -> BootedMachineContext {
        guard let machineName else {
            throw ComposeError.invalidField(
                "machine context",
                reason: "application sandbox has no booted machine"
            )
        }
        guard let snapshot, Self.isRunning(snapshot) else {
            throw ComposeError.machineStopped(machineName, reason: .startRequired)
        }
        return BootedMachineContext(machineName: machineName, snapshot: snapshot)
    }
}
