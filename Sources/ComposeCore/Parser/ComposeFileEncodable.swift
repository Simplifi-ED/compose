import Foundation

extension ComposeFile: Encodable {
    private enum CodingKeys: String, CodingKey {
        case name
        case services
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)

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
