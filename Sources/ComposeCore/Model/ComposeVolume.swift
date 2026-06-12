import Foundation

/// Root-level `volumes:` declaration (minimal form only in v1).
///
/// Supported: empty/no-option declarations and `external: false`. Drivers,
/// custom names, and `external: true` stay out of scope.
public struct ComposeVolume: Sendable, Equatable {
    public let external: Bool?

    public init(external: Bool? = nil) {
        self.external = external
    }
}

extension ComposeVolume: Encodable {
    private enum CodingKeys: String, CodingKey {
        case external
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let external {
            try container.encode(external, forKey: .external)
        }
    }
}

enum ComposeVolumeDecoder {
    private static let supportedRootKeys: Set<String> = ["external"]

    /// Decodes the root `volumes:` map. Entries may be null, empty maps, or
    /// `external: false`; `external: true` is rejected and other options warn.
    static func decodeMap<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) throws -> [String: ComposeVolume] {
        guard container.contains(key) else { return [:] }
        let nested = try container.nestedContainer(
            keyedBy: ComposeSerializeCodingKey.self,
            forKey: key
        )
        var result: [String: ComposeVolume] = [:]
        for name in nested.allKeys {
            if (try? nested.decodeNil(forKey: name)) == true {
                result[name.stringValue] = ComposeVolume()
                continue
            }
            let entry = try nested.nestedContainer(
                keyedBy: ComposeSerializeCodingKey.self,
                forKey: name
            )
            result[name.stringValue] = try decodeEntry(entry, volumeName: name.stringValue)
        }
        return result
    }

    private static func decodeEntry(
        _ entry: KeyedDecodingContainer<ComposeSerializeCodingKey>,
        volumeName: String
    ) throws -> ComposeVolume {
        var external: Bool?
        for key in entry.allKeys {
            guard supportedRootKeys.contains(key.stringValue) else {
                fputs(
                    "warning: volumes: option '\(key.stringValue)' on '\(volumeName)' isn't supported yet\n",
                    stderr
                )
                continue
            }
            external = try entry.decodeIfPresent(Bool.self, forKey: key)
        }
        if external == true {
            throw ComposeError.unsupportedExternalVolume(name: volumeName)
        }
        return ComposeVolume(external: external)
    }
}
