import Foundation

extension ComposeFile: Encodable {
    private enum CodingKeys: String, CodingKey {
        case name
        case services
        case configs
        case secrets
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)

        if !configs.isEmpty {
            var configsContainer = container.nestedContainer(
                keyedBy: ComposeSerializeCodingKey.self,
                forKey: .configs
            )
            for name in configs.keys.sorted() {
                guard let resource = configs[name] else { continue }
                try configsContainer.encode(resource, forKey: ComposeSerializeCodingKey(stringValue: name)!)
            }
        }

        if !secrets.isEmpty {
            var secretsContainer = container.nestedContainer(
                keyedBy: ComposeSerializeCodingKey.self,
                forKey: .secrets
            )
            for name in secrets.keys.sorted() {
                guard let resource = secrets[name] else { continue }
                try secretsContainer.encode(resource, forKey: ComposeSerializeCodingKey(stringValue: name)!)
            }
        }

        var servicesContainer = container.nestedContainer(
            keyedBy: ComposeSerializeCodingKey.self,
            forKey: .services
        )
        for serviceName in services.keys.sorted() {
            guard let service = services[serviceName] else { continue }
            try servicesContainer.encode(
                service,
                forKey: ComposeSerializeCodingKey(stringValue: serviceName)!
            )
        }
    }
}
