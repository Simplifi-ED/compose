import Foundation

public enum MachineStoppedReason: Sendable {
    case noActiveContainers
    case startRequired
}

extension MachineStoppedReason {
    package func message(machineName: String) -> String {
        switch self {
        case .noActiveContainers:
            "Machine '\(machineName)' is stopped. No active containers."
        case .startRequired:
            "Machine '\(machineName)' is stopped. Start it with `container machine run -n \(machineName)`."
        }
    }
}
