import Foundation

public enum ComposeCommandValue: Sendable, Equatable {
    case string(String)
    case list([String])
}

public enum ComposeEnvironment: Sendable, Equatable {
    case map([String: String])
    case list([String])
}

public struct ComposeService: Sendable, Equatable {
    public let image: String?
    public let command: ComposeCommandValue?
    public let ports: [String]
    public let environment: ComposeEnvironment?
    public let containerName: String?

    public init(
        image: String?,
        command: ComposeCommandValue?,
        ports: [String],
        environment: ComposeEnvironment?,
        containerName: String?
    ) {
        self.image = image
        self.command = command
        self.ports = ports
        self.environment = environment
        self.containerName = containerName
    }
}

extension ComposeService: Decodable {
    private enum CodingKeys: String, CodingKey {
        case image
        case command
        case ports
        case environment
        case containerName = "container_name"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        image = try container.decodeIfPresent(String.self, forKey: .image)
        command = try Self.decodeCommand(from: container)
        ports = try container.decodeIfPresent([String].self, forKey: .ports) ?? []
        environment = try Self.decodeEnvironment(from: container)
        containerName = try container.decodeIfPresent(String.self, forKey: .containerName)
    }

    private static func decodeCommand(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> ComposeCommandValue? {
        guard container.contains(.command) else { return nil }
        if let value = try? container.decode(String.self, forKey: .command) {
            return .string(value)
        }
        if let value = try? container.decode([String].self, forKey: .command) {
            return .list(value)
        }
        throw ComposeError.invalidField("command", reason: "expected a string or list of strings")
    }

    private static func decodeEnvironment(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> ComposeEnvironment? {
        guard container.contains(.environment) else { return nil }
        if let value = try? container.decode([String: String].self, forKey: .environment) {
            return .map(value)
        }
        if let value = try? container.decode([String].self, forKey: .environment) {
            return .list(value)
        }
        throw ComposeError.invalidField("environment", reason: "expected a map or list of KEY=VAL strings")
    }
}
