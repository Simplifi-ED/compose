import Foundation

/// Subset of the compose `deploy` block the plugin understands.
///
/// Reads `replicas`, `resources.limits` (`cpus`, `memory`), and
/// `resources.reservations.devices` (`driver: apple`, `capabilities: [gpu]`).
/// Other `deploy` keys are ignored rather than rejected so production compose
/// files keep parsing.
public struct ComposeDeploy: Sendable, Equatable {
    public let replicas: Int?
    public let resources: ComposeDeployResources?

    public init(replicas: Int?, resources: ComposeDeployResources? = nil) {
        self.replicas = replicas
        self.resources = resources
    }

    var hasExportableContent: Bool {
        replicas != nil || resources?.hasContent == true
    }
}

extension ComposeDeploy: Decodable {
    private enum CodingKeys: String, CodingKey {
        case replicas
        case resources
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let replicas = try container.decodeIfPresent(Int.self, forKey: .replicas) {
            guard replicas >= 1 else {
                throw ComposeError.invalidField(
                    "deploy.replicas",
                    reason: "expected an integer of 1 or more (got \(replicas))"
                )
            }
            self.replicas = replicas
        } else {
            self.replicas = nil
        }
        resources = try container.decodeIfPresent(ComposeDeployResources.self, forKey: .resources)
    }
}
