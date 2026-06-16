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
    // MERGE: update ComposeFileMerge, Parser/Compose*Encodable.swift, and with* copy methods
    // when adding stored properties.
    public let image: String?
    public let build: ComposeBuild?
    public let command: ComposeCommandValue?
    public let ports: [String]
    public let volumes: [String]
    public let environment: ComposeEnvironment?
    public let containerName: String?
    public let dependsOn: [ComposeDependency]
    public let profiles: [String]
    public let deploy: ComposeDeploy?
    public let healthcheck: ComposeHealthcheck?
    public let configs: [ComposeServiceMount]
    public let secrets: [ComposeServiceMount]
    public let develop: ComposeDevelop?
    /// Logical network names this service joins; empty means the builtin default network.
    public let networks: [String]
    /// Long-form `networks: { name: null }` removals applied during multi-file merge.
    package let networkNullRemovals: Set<String>
    /// Base directory for relative bind-mount paths; nil uses the CLI compose file directory.
    public let projectDirectory: URL?
    /// Tri-state compose `init:`; nil means unspecified in this file (merge inherits from base).
    public let useInit: Bool?
    /// Hostnames mapped on the macOS host when `up --host-dns` is used (`x-compose.hosts`).
    public let hostnames: [String]
    /// Service platform (`linux/amd64`, `linux/x86_64`, or `linux/arm64`).
    public let platform: String?
    /// SSH agent forwarding (`ssh: default` / `ssh: [default]`).
    public let ssh: [String]?

    public init(
        image: String?,
        build: ComposeBuild? = nil,
        command: ComposeCommandValue?,
        ports: [String],
        volumes: [String] = [],
        environment: ComposeEnvironment?,
        containerName: String?,
        dependsOn: [ComposeDependency] = [],
        profiles: [String] = [],
        deploy: ComposeDeploy? = nil,
        healthcheck: ComposeHealthcheck? = nil,
        configs: [ComposeServiceMount] = [],
        secrets: [ComposeServiceMount] = [],
        develop: ComposeDevelop? = nil,
        networks: [String] = [],
        networkNullRemovals: Set<String> = [],
        projectDirectory: URL? = nil,
        useInit: Bool? = nil,
        hostnames: [String] = [],
        platform: String? = nil,
        ssh: [String]? = nil
    ) {
        self.image = image
        self.build = build
        self.command = command
        self.ports = ports
        self.volumes = volumes
        self.environment = environment
        self.containerName = containerName
        self.dependsOn = dependsOn
        self.profiles = profiles
        self.deploy = deploy
        self.healthcheck = healthcheck
        self.configs = configs
        self.secrets = secrets
        self.develop = develop
        self.networks = networks
        self.networkNullRemovals = networkNullRemovals
        self.projectDirectory = projectDirectory
        self.useInit = useInit
        self.hostnames = hostnames
        self.platform = platform
        self.ssh = ssh
    }

    /// Resolved bind-mount / relative-path root; uses `defaultDirectory` when unset (CLI compose file dir).
    public func projectDirectory(orDefault defaultDirectory: URL) -> URL {
        projectDirectory ?? defaultDirectory
    }

    package func withResolvedImage(_ image: String) -> ComposeService {
        ComposeService(
            image: image,
            build: build,
            command: command,
            ports: ports,
            volumes: volumes,
            environment: environment,
            containerName: containerName,
            dependsOn: dependsOn,
            profiles: profiles,
            deploy: deploy,
            healthcheck: healthcheck,
            configs: configs,
            secrets: secrets,
            develop: develop,
            networks: networks,
            networkNullRemovals: networkNullRemovals,
            projectDirectory: projectDirectory,
            useInit: useInit,
            hostnames: hostnames,
            platform: platform,
            ssh: ssh
        )
    }

    func withProjectDirectory(_ directory: URL) -> ComposeService {
        ComposeService(
            image: image,
            build: build,
            command: command,
            ports: ports,
            volumes: volumes,
            environment: environment,
            containerName: containerName,
            dependsOn: dependsOn,
            profiles: profiles,
            deploy: deploy,
            healthcheck: healthcheck,
            configs: configs,
            secrets: secrets,
            develop: develop,
            networks: networks,
            networkNullRemovals: networkNullRemovals,
            projectDirectory: directory,
            useInit: useInit,
            hostnames: hostnames,
            platform: platform,
            ssh: ssh
        )
    }

    func withDevelop(_ develop: ComposeDevelop?) -> ComposeService {
        ComposeService(
            image: image,
            build: build,
            command: command,
            ports: ports,
            volumes: volumes,
            environment: environment,
            containerName: containerName,
            dependsOn: dependsOn,
            profiles: profiles,
            deploy: deploy,
            healthcheck: healthcheck,
            configs: configs,
            secrets: secrets,
            develop: develop,
            networks: networks,
            networkNullRemovals: networkNullRemovals,
            projectDirectory: projectDirectory,
            useInit: useInit,
            hostnames: hostnames,
            platform: platform,
            ssh: ssh
        )
    }

    func withDeploy(replicas: Int) -> ComposeService {
        ComposeService(
            image: image,
            build: build,
            command: command,
            ports: ports,
            volumes: volumes,
            environment: environment,
            containerName: containerName,
            dependsOn: dependsOn,
            profiles: profiles,
            deploy: ComposeDeploy(replicas: replicas),
            healthcheck: healthcheck,
            configs: configs,
            secrets: secrets,
            develop: develop,
            networks: networks,
            networkNullRemovals: networkNullRemovals,
            projectDirectory: projectDirectory,
            useInit: useInit,
            hostnames: hostnames,
            platform: platform,
            ssh: ssh
        )
    }
}
