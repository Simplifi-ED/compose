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

        for kind in ComposeFileMountKind.allCases {
            let resources = resources(for: kind)
            if !resources.isEmpty {
                try encodeResourceMap(resources, to: &container, forKey: codingKey(for: kind))
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

    private func codingKey(for kind: ComposeFileMountKind) -> CodingKeys {
        switch kind {
        case .config: .configs
        case .secret: .secrets
        }
    }

    private func encodeResourceMap(
        _ resources: [String: ComposeFileResource],
        to container: inout KeyedEncodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws {
        var nested = container.nestedContainer(keyedBy: ComposeSerializeCodingKey.self, forKey: key)
        for name in resources.keys.sorted() {
            guard let resource = resources[name] else { continue }
            try nested.encode(resource, forKey: ComposeSerializeCodingKey(stringValue: name)!)
        }
    }
}
