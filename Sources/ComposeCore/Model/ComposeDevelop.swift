import Foundation

public struct ComposeDevelop: Sendable, Equatable {
    public let watch: [ComposeWatchRule]

    public init(watch: [ComposeWatchRule]) {
        self.watch = watch
    }
}

extension ComposeDevelop: Decodable {
    private enum CodingKeys: String, CodingKey {
        case watch
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        watch = try container.decodeIfPresent([ComposeWatchRule].self, forKey: .watch) ?? []
    }
}

extension ComposeDevelop: Encodable {
    public func encode(to encoder: Encoder) throws {
        guard !watch.isEmpty else { return }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(watch, forKey: .watch)
    }
}
