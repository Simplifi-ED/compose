import Foundation

public struct ComposeFile: Sendable, Equatable {
    public let name: String?
    public let services: [String: ComposeService]
    public let configs: [String: ComposeFileResource]
    public let secrets: [String: ComposeFileResource]
    public let networks: [String: ComposeNetwork]

    public init(
        name: String?,
        services: [String: ComposeService],
        configs: [String: ComposeFileResource] = [:],
        secrets: [String: ComposeFileResource] = [:],
        networks: [String: ComposeNetwork] = [:]
    ) {
        self.name = name
        self.services = services
        self.configs = configs
        self.secrets = secrets
        self.networks = networks
    }

    /// Distinct project directories for the given services (include `defaultDirectory` as fallback root).
    package func projectRoots(for serviceNames: Set<String>, defaultDirectory: URL) -> [URL] {
        var roots: Set<URL> = [defaultDirectory.standardizedFileURL]
        for (serviceName, service) in services where serviceNames.contains(serviceName) {
            roots.insert(service.projectDirectory(orDefault: defaultDirectory).standardizedFileURL)
        }
        for kind in ComposeFileMountKind.allCases {
            for resource in resources(for: kind).values {
                if let root = resource.resolutionRoot {
                    roots.insert(root.standardizedFileURL)
                }
            }
        }
        return Array(roots)
    }
}

extension ComposeFile: Decodable {
    private enum CodingKeys: String, CodingKey {
        case name
        case services
        case configs
        case secrets
        case networks
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        services = try container.decodeIfPresent([String: ComposeService].self, forKey: .services) ?? [:]
        configs = try ComposeFileResourceDecoder.decodeMap(from: container, forKey: .configs, kind: .config)
        secrets = try ComposeFileResourceDecoder.decodeMap(from: container, forKey: .secrets, kind: .secret)
        networks = try ComposeNetworkDecoder.decodeMap(from: container, forKey: .networks)
    }
}
