import Foundation

public struct ComposeFile: Sendable, Equatable {
    public let name: String?
    public let services: [String: ComposeService]

    public init(name: String?, services: [String: ComposeService]) {
        self.name = name
        self.services = services
    }

    /// Distinct project directories for the given services (include `defaultDirectory` as fallback root).
    package func projectRoots(for serviceNames: Set<String>, defaultDirectory: URL) -> [URL] {
        var roots: Set<URL> = [defaultDirectory.standardizedFileURL]
        for (serviceName, service) in services where serviceNames.contains(serviceName) {
            roots.insert(service.projectDirectory(orDefault: defaultDirectory).standardizedFileURL)
        }
        return Array(roots)
    }
}

extension ComposeFile: Decodable {
    private enum CodingKeys: String, CodingKey {
        case name
        case services
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        services = try container.decodeIfPresent([String: ComposeService].self, forKey: .services) ?? [:]
    }
}
