import ContainerAPIClient
import Foundation
import MachineAPIClient

/// Execution target for compose runtime operations (application sandbox or a container machine).
public struct MachineContext: Sendable {
    public static let applicationSandbox = MachineContext(machineName: nil, snapshot: nil)

    public let machineName: String?
    public let snapshot: MachineSnapshot?

    public var isMachineMode: Bool { machineName != nil }

    public init(machineName: String?, snapshot: MachineSnapshot?) {
        self.machineName = machineName
        self.snapshot = snapshot
    }

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

        var dynamicEnv: [String: String] = [:]
        if let sshAuthSock = ProcessInfo.processInfo.environment["SSH_AUTH_SOCK"] {
            dynamicEnv["SSH_AUTH_SOCK"] = sshAuthSock
        }

        var snapshot: MachineSnapshot
        do {
            snapshot = try await machineClient.boot(id: machineName, dynamicEnv: dynamicEnv)
        } catch {
            throw ComposeError.machineBootFailed(machineName, underlying: error)
        }

        guard snapshot.containerId != nil else {
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

    func requireSnapshot() throws -> MachineSnapshot {
        guard let snapshot else {
            throw ComposeError.machineNotRunning(machineName ?? "unknown")
        }
        return snapshot
    }
}
