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
    // MERGE: update ComposeFileMerge when adding stored properties.
    public let image: String?
    public let command: ComposeCommandValue?
    public let ports: [String]
    public let volumes: [String]
    public let environment: ComposeEnvironment?
    public let containerName: String?
    public let dependsOn: [ComposeDependency]
    public let profiles: [String]
    public let deploy: ComposeDeploy?
    public let healthcheck: ComposeHealthcheck?

    public init(
        image: String?,
        command: ComposeCommandValue?,
        ports: [String],
        volumes: [String] = [],
        environment: ComposeEnvironment?,
        containerName: String?,
        dependsOn: [ComposeDependency] = [],
        profiles: [String] = [],
        deploy: ComposeDeploy? = nil,
        healthcheck: ComposeHealthcheck? = nil
    ) {
        self.image = image
        self.command = command
        self.ports = ports
        self.volumes = volumes
        self.environment = environment
        self.containerName = containerName
        self.dependsOn = dependsOn
        self.profiles = profiles
        self.deploy = deploy
        self.healthcheck = healthcheck
    }
}

extension ComposeService: Decodable {
    private enum CodingKeys: String, CodingKey {
        case image
        case command
        case ports
        case volumes
        case environment
        case containerName = "container_name"
        case dependsOn = "depends_on"
        case profiles
        case deploy
        case healthcheck
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        image = try container.decodeIfPresent(String.self, forKey: .image)
        command = try Self.decodeCommand(from: container)
        ports = try container.decodeIfPresent([String].self, forKey: .ports) ?? []
        volumes = try Self.decodeVolumes(from: container)
        environment = try Self.decodeEnvironment(from: container)
        containerName = try container.decodeIfPresent(String.self, forKey: .containerName)
        dependsOn = try Self.decodeDependsOn(from: container)
        profiles = try Self.decodeProfiles(from: container)
        deploy = try Self.decodeDeploy(from: container)
        healthcheck = try Self.decodeHealthcheck(from: container)
    }

    private static func decodeDeploy(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> ComposeDeploy? {
        guard container.contains(.deploy) else { return nil }
        do {
            return try container.decode(ComposeDeploy.self, forKey: .deploy)
        } catch let error as ComposeError {
            throw error
        } catch {
            throw ComposeError.invalidField("deploy", reason: "expected a map with an integer replicas value")
        }
    }

    private static func decodeHealthcheck(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> ComposeHealthcheck? {
        guard container.contains(.healthcheck) else { return nil }
        do {
            return try container.decode(ComposeHealthcheck.self, forKey: .healthcheck)
        } catch let error as ComposeError {
            throw error
        } catch {
            throw ComposeError.invalidField("healthcheck", reason: "expected a map with a test command")
        }
    }

    private static func decodeProfiles(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> [String] {
        guard container.contains(.profiles) else { return [] }
        if let value = try? container.decode(String.self, forKey: .profiles) {
            return [value]
        }
        if let value = try? container.decode([String].self, forKey: .profiles) {
            return value
        }
        throw ComposeError.invalidField("profiles", reason: "expected a string or list of profile names")
    }

    private static func decodeDependsOn(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> [ComposeDependency] {
        guard container.contains(.dependsOn) else { return [] }
        if let value = try? container.decode([String].self, forKey: .dependsOn) {
            return value.map { ComposeDependency(service: $0, condition: .orderingOnly) }
        }
        if let value = try? container.decode([String: DependsOnEntry].self, forKey: .dependsOn) {
            return try value.keys.sorted().map { serviceName in
                let entry = value[serviceName]!
                let condition = try DependsOnCondition.parse(entry.condition)
                return ComposeDependency(service: serviceName, condition: condition)
            }
        }
        throw ComposeError.invalidField(
            "depends_on",
            reason: "expected a list of service names or a map of service conditions"
        )
    }

    private static func decodeVolumes(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> [String] {
        guard container.contains(.volumes) else { return [] }
        if let value = try? container.decode([String].self, forKey: .volumes) {
            return value
        }
        throw ComposeError.invalidField("volumes", reason: "expected a list of host:container strings")
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

private struct DependsOnEntry: Decodable {
    let condition: String
}
