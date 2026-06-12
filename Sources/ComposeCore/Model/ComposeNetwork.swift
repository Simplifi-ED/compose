import Foundation

/// Root-level `networks:` declaration (minimal form only in v1).
///
/// Supported: empty/no-option declarations and `external: false`. Drivers, IPAM,
/// custom names, and `external: true` stay out of scope.
public struct ComposeNetwork: Sendable, Equatable {
    public let external: Bool?

    public init(external: Bool? = nil) {
        self.external = external
    }
}

extension ComposeNetwork: Encodable {
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

enum ComposeNetworkDecoder {
    private static let supportedRootKeys: Set<String> = ["external"]

    /// Decodes the root `networks:` map. Entries may be null, empty maps, or
    /// `external: false`; `external: true` is rejected and other options warn.
    static func decodeMap<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) throws -> [String: ComposeNetwork] {
        guard container.contains(key) else { return [:] }
        let nested = try container.nestedContainer(
            keyedBy: ComposeSerializeCodingKey.self,
            forKey: key
        )
        var result: [String: ComposeNetwork] = [:]
        for name in nested.allKeys {
            if (try? nested.decodeNil(forKey: name)) == true {
                result[name.stringValue] = ComposeNetwork()
                continue
            }
            let entry = try nested.nestedContainer(
                keyedBy: ComposeSerializeCodingKey.self,
                forKey: name
            )
            result[name.stringValue] = try decodeEntry(entry, networkName: name.stringValue)
        }
        return result
    }

    private static func decodeEntry(
        _ entry: KeyedDecodingContainer<ComposeSerializeCodingKey>,
        networkName: String
    ) throws -> ComposeNetwork {
        var external: Bool?
        for key in entry.allKeys {
            guard supportedRootKeys.contains(key.stringValue) else {
                fputs(
                    "warning: networks: option '\(key.stringValue)' on '\(networkName)' isn't supported yet\n",
                    stderr
                )
                continue
            }
            external = try entry.decodeIfPresent(Bool.self, forKey: key)
        }
        if external == true {
            throw ComposeError.unsupportedExternalNetwork(name: networkName)
        }
        return ComposeNetwork(external: external)
    }

    /// Decodes service-level `networks:` membership — short list or
    /// long map form with empty entries (per-network options are rejected).
    /// `nullRemovals` records long-form `name: null` disconnect overrides for merge.
    static func decodeServiceNetworks<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) throws -> (names: [String], nullRemovals: Set<String>) {
        guard container.contains(key) else { return ([], []) }

        if let names = try? container.decode([String].self, forKey: key) {
            var seen: Set<String> = []
            return (
                names.filter { seen.insert($0).inserted }.sorted(),
                []
            )
        }
        guard let nested = try? container.nestedContainer(
            keyedBy: ComposeSerializeCodingKey.self,
            forKey: key
        ) else {
            throw ComposeError.invalidField(
                "networks",
                reason: "expected a list of network names or a map of network entries"
            )
        }
        var memberships: [String] = []
        var nullRemovals: Set<String> = []
        for name in nested.allKeys.sorted(by: { $0.stringValue < $1.stringValue }) {
            if (try? nested.decodeNil(forKey: name)) == true {
                nullRemovals.insert(name.stringValue)
                continue
            }
            let entry = try nested.nestedContainer(
                keyedBy: ComposeSerializeCodingKey.self,
                forKey: name
            )
            if let option = entry.allKeys.first {
                throw ComposeError.unsupportedNetworkOption(
                    network: name.stringValue,
                    option: option.stringValue
                )
            }
            memberships.append(name.stringValue)
        }
        return (memberships.sorted(), nullRemovals)
    }
}
