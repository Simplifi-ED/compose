import Foundation

/// One `include:` list item after normalizing short and long syntax.
struct ComposeIncludeEntry: Sendable, Equatable {
    let paths: [String]
    let envFile: [String]?
    let projectDirectory: String?
    /// True for bare path strings; false for `{ path:, env_file:, project_directory: }` objects.
    let usesShortSyntax: Bool

    init(
        paths: [String],
        envFile: [String]? = nil,
        projectDirectory: String? = nil,
        usesShortSyntax: Bool = false
    ) {
        self.paths = paths
        self.envFile = envFile
        self.projectDirectory = projectDirectory
        self.usesShortSyntax = usesShortSyntax
    }

    init(path: String) {
        self.init(paths: [path], usesShortSyntax: true)
    }
}

extension ComposeIncludeEntry: Decodable {
    private enum CodingKeys: String, CodingKey {
        case path
        case envFile = "env_file"
        case projectDirectory = "project_directory"
    }

    init(from decoder: Decoder) throws {
        if let singlePath = try? decoder.singleValueContainer().decode(String.self) {
            self.init(paths: [singlePath], usesShortSyntax: true)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let pathValue: [String]
        if let single = try? container.decode(String.self, forKey: .path) {
            pathValue = [single]
        } else if let multiple = try? container.decode([String].self, forKey: .path) {
            guard !multiple.isEmpty else {
                throw ComposeError.invalidInclude(reason: "path must list at least one compose file")
            }
            pathValue = multiple
        } else {
            throw ComposeError.invalidInclude(reason: "path is required and must be a string or list of strings")
        }

        let envFile: [String]?
        if container.contains(.envFile) {
            if let single = try? container.decode(String.self, forKey: .envFile) {
                envFile = [single]
            } else if let multiple = try? container.decode([String].self, forKey: .envFile) {
                envFile = multiple
            } else {
                throw ComposeError.invalidInclude(reason: "env_file must be a string or list of strings")
            }
        } else {
            envFile = nil
        }

        let projectDirectory = try container.decodeIfPresent(String.self, forKey: .projectDirectory)
        self.init(paths: pathValue, envFile: envFile, projectDirectory: projectDirectory, usesShortSyntax: false)
    }
}

/// Decode target before `include:` expansion; public `ComposeFile` stays include-free.
struct ComposeFileDocument: Sendable, Equatable {
    let name: String?
    let services: [String: ComposeService]
    let configs: [String: ComposeFileResource]
    let secrets: [String: ComposeFileResource]
    let include: [ComposeIncludeEntry]

    init(
        name: String?,
        services: [String: ComposeService],
        configs: [String: ComposeFileResource] = [:],
        secrets: [String: ComposeFileResource] = [:],
        include: [ComposeIncludeEntry] = []
    ) {
        self.name = name
        self.services = services
        self.configs = configs
        self.secrets = secrets
        self.include = include
    }
}

extension ComposeFileDocument: Decodable {
    private enum CodingKeys: String, CodingKey {
        case name
        case services
        case configs
        case secrets
        case include
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        services = try container.decodeIfPresent([String: ComposeService].self, forKey: .services) ?? [:]
        configs = try ComposeFileResourceDecoder.decodeMap(from: container, forKey: .configs, kind: .config)
        secrets = try ComposeFileResourceDecoder.decodeMap(from: container, forKey: .secrets, kind: .secret)
        include = try Self.decodeInclude(from: container)
    }

    private static func decodeInclude(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> [ComposeIncludeEntry] {
        guard container.contains(.include) else { return [] }

        if let singlePath = try? container.decode(String.self, forKey: .include) {
            return [ComposeIncludeEntry(path: singlePath)]
        }
        if let entries = try? container.decode([ComposeIncludeEntry].self, forKey: .include) {
            return entries
        }
        if let entry = try? container.decode(ComposeIncludeEntry.self, forKey: .include) {
            return [entry]
        }
        throw ComposeError.invalidInclude(
            reason: "include must be a path string, a list of paths, or a list of include objects"
        )
    }
}
