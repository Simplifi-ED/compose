import Foundation

package enum CpPathRef: Equatable, Sendable {
    case local(String)
    case service(name: String, path: String)

    package var serviceName: String? {
        switch self {
        case .local:
            return nil
        case .service(let name, _):
            return name
        }
    }

    package var isService: Bool {
        if case .service = self { return true }
        return false
    }

    package static func parse(_ ref: String) throws -> CpPathRef {
        let trimmed = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ComposeError.invalidCpPath(reason: "path is empty")
        }

        let parts = trimmed.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        switch parts.count {
        case 1:
            return .local(String(parts[0]))
        case 2:
            let serviceName = String(parts[0])
            let containerPath = String(parts[1])
            guard !serviceName.isEmpty else {
                throw ComposeError.invalidCpPath(
                    reason: "service name is empty in '\(ref)'"
                )
            }
            guard containerPath.hasPrefix("/") else {
                throw ComposeError.invalidCpPath(
                    reason: "container path in '\(ref)' must be absolute (start with /)"
                )
            }
            return .service(name: serviceName, path: containerPath)
        default:
            throw ComposeError.invalidCpPath(reason: "invalid path '\(ref)'")
        }
    }
}
