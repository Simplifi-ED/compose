import Foundation

/// Subset of the compose `deploy` block the plugin understands.
///
/// Only `replicas` is read; other `deploy` keys (resources, placement,
/// update_config, ...) are ignored rather than rejected so production
/// compose files keep parsing.
public struct ComposeDeploy: Sendable, Equatable {
    public let replicas: Int?

    public init(replicas: Int?) {
        self.replicas = replicas
    }
}

extension ComposeDeploy: Decodable {
    private enum CodingKeys: String, CodingKey {
        case replicas
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let replicas = try container.decodeIfPresent(Int.self, forKey: .replicas) else {
            self.replicas = nil
            return
        }
        guard replicas >= 1 else {
            throw ComposeError.invalidField(
                "deploy.replicas",
                reason: "expected an integer of 1 or more (got \(replicas))"
            )
        }
        self.replicas = replicas
    }
}
