import Foundation

extension ComposeService: Decodable {
    private enum CodingKeys: String, CodingKey {
        case image
        case build
        case command
        case ports
        case volumes
        case environment
        case containerName = "container_name"
        case dependsOn = "depends_on"
        case profiles
        case deploy
        case healthcheck
        case configs
        case secrets
        case develop
        case networks
        case networkMode = "network_mode"
        case useInit = "init"
        case xCompose = "x-compose"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard !container.contains(.networkMode) else {
            throw ComposeError.invalidField(
                "network_mode",
                reason: "isn't supported; attach the service to a project network with networks: instead"
            )
        }
        image = try container.decodeIfPresent(String.self, forKey: .image)
        build = try Self.decodeBuild(from: container)
        command = try Self.decodeCommand(from: container)
        ports = try container.decodeIfPresent([String].self, forKey: .ports) ?? []
        volumes = try Self.decodeVolumes(from: container)
        environment = try Self.decodeEnvironment(from: container)
        containerName = try container.decodeIfPresent(String.self, forKey: .containerName)
        dependsOn = try Self.decodeDependsOn(from: container)
        profiles = try Self.decodeProfiles(from: container)
        deploy = try Self.decodeDeploy(from: container)
        healthcheck = try Self.decodeHealthcheck(from: container)
        configs = try Self.decodeServiceMounts(from: container, key: .configs, kind: .config)
        secrets = try Self.decodeServiceMounts(from: container, key: .secrets, kind: .secret)
        develop = try Self.decodeDevelop(from: container)
        useInit = try Self.decodeUseInit(from: container)
        let decodedNetworks = try ComposeNetworkDecoder.decodeServiceNetworks(from: container, forKey: .networks)
        networks = decodedNetworks.names
        networkNullRemovals = decodedNetworks.nullRemovals
        hostnames = try Self.decodeHostnames(from: container)
        projectDirectory = nil
    }

    private static func decodeHostnames(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> [String] {
        guard container.contains(.xCompose) else { return [] }
        let nested: KeyedDecodingContainer<XComposeKeys>
        do {
            nested = try container.nestedContainer(keyedBy: XComposeKeys.self, forKey: .xCompose)
        } catch {
            throw ComposeError.invalidField("x-compose", reason: "expected a map with a hosts list")
        }
        warnUnsupportedXComposeKeys(in: nested)
        guard nested.contains(.hosts) else { return [] }
        if let value = try? nested.decode([String].self, forKey: .hosts) {
            return value
        }
        throw ComposeError.invalidField("x-compose.hosts", reason: "expected a list of hostnames")
    }

    private static func warnUnsupportedXComposeKeys(
        in container: KeyedDecodingContainer<XComposeKeys>
    ) {
        for key in container.allKeys where key != .hosts {
            fputs("warning: x-compose: key '\(key.stringValue)' isn't supported yet\n", stderr)
        }
    }

    private static func decodeBuild(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> ComposeBuild? {
        guard container.contains(.build) else { return nil }
        if let contextPath = try? container.decode(String.self, forKey: .build) {
            guard !contextPath.isEmpty else {
                throw ComposeError.invalidField("build", reason: "expected a non-empty context path")
            }
            return ComposeBuild(context: contextPath)
        }
        warnUnsupportedBuildKeys(in: container)
        do {
            return try container.decode(ComposeBuild.self, forKey: .build)
        } catch let error as ComposeError {
            throw error
        } catch {
            throw ComposeError.invalidField(
                "build",
                reason: "expected a context path string or a map with context"
            )
        }
    }

    private static func warnUnsupportedBuildKeys(
        in container: KeyedDecodingContainer<CodingKeys>
    ) {
        guard let nested = try? container.nestedContainer(
            keyedBy: ComposeBuildDynamicKey.self,
            forKey: .build
        ) else {
            return
        }
        for key in nested.allKeys where !ComposeBuild.supportedKeys.contains(key.stringValue) {
            fputs("warning: build: key '\(key.stringValue)' isn't supported yet\n", stderr)
        }
    }

    private static func decodeUseInit(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> Bool? {
        guard container.contains(.useInit) else { return nil }
        do {
            return try container.decode(Bool.self, forKey: .useInit)
        } catch {
            throw ComposeError.invalidField("init", reason: "expected true or false")
        }
    }

    private static func decodeDevelop(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> ComposeDevelop? {
        guard container.contains(.develop) else { return nil }
        do {
            return try container.decode(ComposeDevelop.self, forKey: .develop)
        } catch let error as ComposeError {
            throw error
        } catch {
            throw ComposeError.invalidField("develop", reason: "expected a map with a watch list")
        }
    }

    private static func decodeServiceMounts(
        from container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys,
        kind: ComposeFileMountKind
    ) throws -> [ComposeServiceMount] {
        guard container.contains(key) else { return [] }

        if let strings = try? container.decode([String].self, forKey: key) {
            return try strings.map { try ComposeServiceMountDecoder.decodeShortSyntax($0, kind: kind) }
        }
        if let entries = try? container.decode([ComposeServiceMountEntry].self, forKey: key) {
            return entries.map { ComposeServiceMount(source: $0.source, target: $0.target) }
        }
        throw ComposeError.invalidField(
            kind.rootFieldName,
            reason: "expected a list of names or source/target maps"
        )
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

private enum XComposeKeys: String, CodingKey {
    case hosts
}

private struct ComposeBuildDynamicKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        return nil
    }
}
