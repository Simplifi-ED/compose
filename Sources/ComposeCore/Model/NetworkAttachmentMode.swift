import Foundation

/// Compose network attachment mode for root `networks:` declarations.
public enum NetworkAttachmentMode: String, Sendable, Equatable, Codable {
    case nat
    case bridge
}

extension NetworkAttachmentMode {
    package static func parse(_ raw: String) throws -> NetworkAttachmentMode {
        switch raw.lowercased() {
        case "nat", "":
            return .nat
        case "bridge":
            return .bridge
        default:
            throw ComposeError.invalidField(
                "x-compose.network.mode",
                reason: "expected 'nat' or 'bridge', got '\(raw)'"
            )
        }
    }
}
