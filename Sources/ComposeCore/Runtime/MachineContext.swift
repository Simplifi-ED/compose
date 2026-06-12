import ContainerAPIClient
import ContainerResource
import Foundation
import MachineAPIClient

package enum MachineStoppedPolicy: Sendable {
    case allowStopped
    case gracefulExit
    case requireRunning
}

package enum MachineContextResolution: Sendable {
    case ready(MachineContext)
    case stoppedGracefully

    package var machineContext: MachineContext {
        get throws {
            guard case .ready(let context) = self else {
                throw ComposeError.invalidField(
                    "machine context",
                    reason: "machine is stopped; use machineContextIfReady for graceful exit"
                )
            }
            return context
        }
    }

    package var machineContextIfReady: MachineContext? {
        guard case .ready(let context) = self else { return nil }
        return context
    }
}

/// Execution target for compose runtime operations (application sandbox or a container machine).
public struct MachineContext: Sendable {
    public static let applicationSandbox = MachineContext(machineName: nil, snapshot: nil)

    public let machineName: String?
    public let snapshot: MachineSnapshot?

    public var isMachineMode: Bool { machineName != nil }

    package var isMachineRunning: Bool {
        guard isMachineMode, let snapshot else { return false }
        return Self.isRunning(snapshot)
    }

    public init(machineName: String?, snapshot: MachineSnapshot?) {
        self.machineName = machineName
        self.snapshot = snapshot
    }

    /// Validates machine existence and inspects state without booting.
    public static func resolve(machineName: String?) async throws -> MachineContext {
        guard let machineName else {
            return .applicationSandbox
        }
        try MachineNameValidator.validate(machineName)

        let machineClient = MachineClient()
        let machines = try await machineClient.list()
        guard machines.contains(where: { $0.id == machineName }) else {
            throw ComposeError.machineNotFound(machineName)
        }

        let snapshot = try await machineClient.inspect(id: machineName)
        return MachineContext(machineName: machineName, snapshot: snapshot)
    }

    /// Boots the machine when stopped and runs first-boot setup when needed.
    ///
    /// Returns a context suitable for ``bootedContext()`` on mutating machine-mode paths.
    public func ensureBooted() async throws -> MachineContext {
        guard let machineName else { return self }

        if isMachineRunning, let snapshot, snapshot.initialized {
            return self
        }

        let machineClient = MachineClient()
        var snapshot: MachineSnapshot
        if isMachineRunning, let existing = self.snapshot {
            snapshot = existing
        } else {
            fputs("Booting machine '\(machineName)'...\n", stderr)
            var dynamicEnv: [String: String] = [:]
            if let sshAuthSock = ProcessInfo.processInfo.environment["SSH_AUTH_SOCK"] {
                dynamicEnv["SSH_AUTH_SOCK"] = sshAuthSock
            }
            do {
                snapshot = try await machineClient.boot(id: machineName, dynamicEnv: dynamicEnv)
            } catch {
                throw ComposeError.machineBootFailed(machineName, underlying: error)
            }
        }

        guard Self.isRunning(snapshot) else {
            throw ComposeError.machineNotRunning(machineName)
        }

        if !snapshot.initialized {
            try await MachineFirstBoot.runUserSetup(snapshot: snapshot)
            snapshot = try await machineClient.inspect(id: machineName)
        }

        return MachineContext(machineName: machineName, snapshot: snapshot)
    }

    public func printExecutionBanner() {
        if let machineName {
            fputs("Execution context: container machine '\(machineName)'\n", stderr)
        } else {
            fputs("Execution context: application sandbox\n", stderr)
        }
    }

    package static func applyStoppedPolicy(
        _ context: MachineContext,
        policy: MachineStoppedPolicy
    ) throws -> MachineContextResolution {
        guard context.isMachineMode, !context.isMachineRunning else {
            return .ready(context)
        }
        switch policy {
        case .allowStopped:
            return .ready(context)
        case .gracefulExit:
            guard let machineName = context.machineName else {
                return .ready(context)
            }
            let message = MachineStoppedReason.noActiveContainers.message(machineName: machineName)
            fputs("\(message)\n", stderr)
            return .stoppedGracefully
        case .requireRunning:
            guard let machineName = context.machineName else {
                return .ready(context)
            }
            throw ComposeError.machineStopped(machineName, reason: .startRequired)
        }
    }

    package static func isRunning(_ snapshot: MachineSnapshot) -> Bool {
        snapshot.status == .running && snapshot.containerId != nil
    }
}
