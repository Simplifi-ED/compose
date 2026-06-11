import Foundation

public struct ComposeWatchRule: Sendable, Equatable {
    public let path: String
    public let target: String?
    public let action: ComposeWatchAction
    public let ignore: [String]
    public let initialSync: Bool

    public init(
        path: String,
        target: String? = nil,
        action: ComposeWatchAction,
        ignore: [String] = [],
        initialSync: Bool = false
    ) {
        self.path = path
        self.target = target
        self.action = action
        self.ignore = ignore
        self.initialSync = initialSync
    }
}

extension ComposeWatchRule: Decodable {
    private enum CodingKeys: String, CodingKey {
        case path
        case target
        case action
        case ignore
        case initialSync = "initial_sync"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        target = try container.decodeIfPresent(String.self, forKey: .target)
        let actionRaw = try container.decode(String.self, forKey: .action)
        action = try ComposeWatchAction.parse(actionRaw)
        ignore = try container.decodeIfPresent([String].self, forKey: .ignore) ?? []
        initialSync = try container.decodeIfPresent(Bool.self, forKey: .initialSync) ?? false
    }
}

extension ComposeWatchRule: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encodeIfPresent(target, forKey: .target)
        try container.encode(action.rawValue, forKey: .action)
        if !ignore.isEmpty {
            try container.encode(ignore, forKey: .ignore)
        }
        if initialSync {
            try container.encode(initialSync, forKey: .initialSync)
        }
    }
}
