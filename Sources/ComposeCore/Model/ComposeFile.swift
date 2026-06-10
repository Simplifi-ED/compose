import Foundation

public struct ComposeFile: Sendable, Equatable {
    public let name: String?
    public let services: [String: ComposeService]
}

extension ComposeFile: Decodable {
    private enum CodingKeys: String, CodingKey {
        case name
        case services
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        services = try container.decodeIfPresent([String: ComposeService].self, forKey: .services) ?? [:]
    }
}
