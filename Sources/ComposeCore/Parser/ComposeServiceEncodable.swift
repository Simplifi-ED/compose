import Foundation

extension ComposeCommandValue: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let text):
            try container.encode(text)
        case .list(let items):
            try container.encode(items)
        }
    }
}

extension ComposeEnvironment: Encodable {
    public func encode(to encoder: Encoder) throws {
        switch self {
        case .map(let entries):
            var container = encoder.container(keyedBy: ComposeSerializeCodingKey.self)
            for key in entries.keys.sorted() {
                try container.encode(entries[key]!, forKey: ComposeSerializeCodingKey(stringValue: key)!)
            }
        case .list(let entries):
            var container = encoder.singleValueContainer()
            try container.encode(entries)
        }
    }
}

extension ComposeDeploy: Encodable {
    private enum CodingKeys: String, CodingKey {
        case replicas
        case resources
    }

    public func encode(to encoder: Encoder) throws {
        guard hasExportableContent else { return }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(replicas, forKey: .replicas)
        if let resources, resources.limits?.hasContent == true {
            try container.encode(resources, forKey: .resources)
        }
    }
}

extension ComposeService: Encodable {
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
        case useInit = "init"
        case xCompose = "x-compose"
        case platform
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(image, forKey: .image)
        try encodeBuild(to: &container)
        try container.encodeIfPresent(command, forKey: .command)
        if !ports.isEmpty {
            try container.encode(ports, forKey: .ports)
        }
        if !volumes.isEmpty {
            try container.encode(volumes, forKey: .volumes)
        }
        try container.encodeIfPresent(environment, forKey: .environment)
        try container.encodeIfPresent(containerName, forKey: .containerName)
        if !dependsOn.isEmpty {
            try encodeDependsOn(to: &container)
        }
        if !profiles.isEmpty {
            try container.encode(profiles, forKey: .profiles)
        }
        if let deploy, deploy.hasExportableContent {
            try container.encode(deploy, forKey: .deploy)
        }
        try container.encodeIfPresent(healthcheck, forKey: .healthcheck)
        if let develop, !develop.watch.isEmpty {
            try container.encode(develop, forKey: .develop)
        }
        for kind in ComposeFileMountKind.allCases {
            let serviceMounts = mounts(for: kind)
            if !serviceMounts.isEmpty {
                try encodeServiceMounts(serviceMounts, kind: kind, to: &container)
            }
        }
        if !networks.isEmpty {
            try container.encode(networks, forKey: .networks)
        }
        if useInit == true {
            try container.encode(true, forKey: .useInit)
        }
        if let platform {
            try container.encode(try PlatformPlanning.normalize(platform), forKey: .platform)
        }
        try encodeXComposeHosts(to: &container)
    }

    private func encodeXComposeHosts(to container: inout KeyedEncodingContainer<CodingKeys>) throws {
        guard !hostnames.isEmpty else { return }
        var extensionContainer = container.nestedContainer(keyedBy: XComposeEncodeKeys.self, forKey: .xCompose)
        try extensionContainer.encode(hostnames, forKey: .hosts)
    }

    private func encodeServiceMounts(
        _ serviceMounts: [ComposeServiceMount],
        kind: ComposeFileMountKind,
        to container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        let key: CodingKeys = switch kind {
        case .config: .configs
        case .secret: .secrets
        }
        var list = container.nestedUnkeyedContainer(forKey: key)
        for mount in serviceMounts {
            try list.encode(ResolvedServiceMountEncoder(mount: mount, kind: kind))
        }
    }

    private func encodeBuild(to container: inout KeyedEncodingContainer<CodingKeys>) throws {
        guard let build else { return }
        if build.dockerfile == nil, build.args.isEmpty, build.target == nil {
            try container.encode(build.context, forKey: .build)
            return
        }
        try container.encode(build, forKey: .build)
    }

    private func encodeDependsOn(to container: inout KeyedEncodingContainer<CodingKeys>) throws {
        if dependsOn.allSatisfy({ $0.condition == .orderingOnly }) {
            try container.encode(dependsOn.map(\.service), forKey: .dependsOn)
            return
        }

        var dependsContainer = container.nestedContainer(
            keyedBy: ComposeSerializeCodingKey.self,
            forKey: .dependsOn
        )
        for dependency in dependsOn {
            let condition = ComposeSerializeKeys.exportCondition(dependency.condition)
            try dependsContainer.encode(
                DependsOnConditionExport(condition: condition),
                forKey: ComposeSerializeCodingKey(stringValue: dependency.service)!
            )
        }
    }
}

private struct DependsOnConditionExport: Encodable {
    let condition: String
}

private enum XComposeEncodeKeys: String, CodingKey {
    case hosts
}

private struct ResolvedServiceMountEncoder: Encodable {
    let mount: ComposeServiceMount
    let kind: ComposeFileMountKind

    func encode(to encoder: Encoder) throws {
        try mount.encodeResolved(kind: kind, to: encoder)
    }
}
