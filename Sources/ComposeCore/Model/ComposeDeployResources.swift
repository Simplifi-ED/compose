import Foundation

public struct ComposeResourceLimits: Sendable, Equatable {
    public let cpus: String?
    public let memory: String?

    public init(cpus: String?, memory: String?) {
        self.cpus = cpus
        self.memory = memory
    }

    var hasContent: Bool {
        cpus != nil || memory != nil
    }
}

public struct ComposeDeployResources: Sendable, Equatable {
    public let limits: ComposeResourceLimits?

    public init(limits: ComposeResourceLimits?) {
        self.limits = limits
    }
}

extension ComposeResourceLimits: Codable {
    private enum CodingKeys: String, CodingKey {
        case cpus
        case memory
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cpus = try Self.decodeOptionalString(forKey: .cpus, from: container)
        memory = try Self.decodeOptionalString(forKey: .memory, from: container)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(cpus, forKey: .cpus)
        try container.encodeIfPresent(memory, forKey: .memory)
    }

    private static func decodeOptionalString(
        forKey key: CodingKeys,
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> String? {
        if let value = try container.decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try container.decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try container.decodeIfPresent(Double.self, forKey: key) {
            return String(value)
        }
        return nil
    }
}

extension ComposeDeployResources: Codable {
    private enum CodingKeys: String, CodingKey {
        case limits
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        limits = try container.decodeIfPresent(ComposeResourceLimits.self, forKey: .limits)
    }

    public func encode(to encoder: Encoder) throws {
        guard let limits, limits.hasContent else { return }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(limits, forKey: .limits)
    }
}
