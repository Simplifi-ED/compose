import Foundation

/// Root-level `configs:` / `secrets:` file definition (`file:` source only in v1).
public struct ComposeFileResource: Sendable, Equatable {
    public let file: String
    public let external: Bool?
    /// Directory used to resolve relative `file:` paths; set when the compose file is parsed.
    public let resolutionRoot: URL?

    public init(file: String, external: Bool? = nil, resolutionRoot: URL? = nil) {
        self.file = file
        self.external = external
        self.resolutionRoot = resolutionRoot
    }

    func withResolutionRoot(_ root: URL) -> ComposeFileResource {
        ComposeFileResource(file: file, external: external, resolutionRoot: root)
    }

    static func decodeEntry(
        from container: KeyedDecodingContainer<ComposeResourceEntryCodingKeys>,
        kind: ComposeFileMountKind
    ) throws -> ComposeFileResource {
        let external = try container.decodeIfPresent(Bool.self, forKey: .external)
        if external == true {
            throw ComposeError.unsupportedExternalResource(kind: kind)
        }
        guard let file = try container.decodeIfPresent(String.self, forKey: .file), !file.isEmpty else {
            throw ComposeError.invalidField(
                kind.rootFieldName,
                reason: "expected a file path for non-external \(kind.rootFieldName)"
            )
        }
        return ComposeFileResource(file: file, external: external, resolutionRoot: nil)
    }
}

enum ComposeResourceEntryCodingKeys: String, CodingKey {
    case file
    case external
}

extension ComposeFileResource: Encodable {
    private enum CodingKeys: String, CodingKey {
        case file
        case external
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(file, forKey: .file)
        if let external {
            try container.encode(external, forKey: .external)
        }
    }
}

enum ComposeFileResourceDecoder {
    static func decodeMap<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>,
        forKey key: Key,
        kind: ComposeFileMountKind
    ) throws -> [String: ComposeFileResource] {
        guard container.contains(key) else { return [:] }
        let nested = try container.nestedContainer(
            keyedBy: ComposeSerializeCodingKey.self,
            forKey: key
        )
        var result: [String: ComposeFileResource] = [:]
        for name in nested.allKeys {
            let entry = try nested.nestedContainer(
                keyedBy: ComposeResourceEntryCodingKeys.self,
                forKey: name
            )
            result[name.stringValue] = try ComposeFileResource.decodeEntry(from: entry, kind: kind)
        }
        return result
    }

    static func stamp(
        _ resources: [String: ComposeFileResource],
        resolutionRoot: URL
    ) -> [String: ComposeFileResource] {
        resources.mapValues { $0.withResolutionRoot(resolutionRoot) }
    }
}
