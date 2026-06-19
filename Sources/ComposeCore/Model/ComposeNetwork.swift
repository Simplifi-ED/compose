import Foundation

/// Root-level `networks:` declaration (minimal form only in v1).
///
/// Supported: empty/no-option declarations, `external: false`, and
/// `x-compose.network.mode` / `driver: bridge` for bridged attachment.
/// Other drivers, IPAM, custom names, and `external: true` stay out of scope.
public struct ComposeNetwork: Sendable, Equatable {
    public let external: Bool?
    public let mode: NetworkAttachmentMode

    public init(external: Bool? = nil, mode: NetworkAttachmentMode = .nat) {
        self.external = external
        self.mode = mode
    }
}

extension ComposeNetwork: Encodable {
    private enum CodingKeys: String, CodingKey {
        case external
        case xCompose = "x-compose"
    }

    private enum XComposeKeys: String, CodingKey {
        case network
    }

    private enum NetworkKeys: String, CodingKey {
        case mode
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let external {
            try container.encode(external, forKey: .external)
        }
        if mode == .bridge {
            var xCompose = container.nestedContainer(keyedBy: XComposeKeys.self, forKey: .xCompose)
            var network = xCompose.nestedContainer(keyedBy: NetworkKeys.self, forKey: .network)
            try network.encode(mode.rawValue, forKey: .mode)
        }
    }
}

enum ComposeNetworkDecoder {
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
        var mode: NetworkAttachmentMode = .nat
        var driverBridge = false
        for key in entry.allKeys {
            switch key.stringValue {
            case "external":
                external = try entry.decodeIfPresent(Bool.self, forKey: key)
            case "driver":
                let driver = try entry.decode(String.self, forKey: key)
                if driver.lowercased() == "bridge" {
                    driverBridge = true
                } else {
                    fputs(
                        "warning: networks: driver '\(driver)' on '\(networkName)' isn't supported yet\n",
                        stderr
                    )
                }
            case "x-compose":
                mode = try decodeXComposeMode(from: entry, forKey: key, networkName: networkName)
            default:
                fputs(
                    "warning: networks: option '\(key.stringValue)' on '\(networkName)' isn't supported yet\n",
                    stderr
                )
            }
        }
        if driverBridge {
            if mode == .nat {
                mode = .bridge
            } else if mode != .bridge {
                fputs(
                    "warning: networks: driver and x-compose.network.mode disagree on '\(networkName)'; "
                        + "using x-compose.network.mode\n",
                    stderr
                )
            }
        }
        if external == true {
            throw ComposeError.unsupportedExternalNetwork(name: networkName)
        }
        return ComposeNetwork(external: external, mode: mode)
    }

    private static func decodeXComposeMode(
        from entry: KeyedDecodingContainer<ComposeSerializeCodingKey>,
        forKey key: ComposeSerializeCodingKey,
        networkName: String
    ) throws -> NetworkAttachmentMode {
        let xCompose = try entry.nestedContainer(keyedBy: ComposeSerializeCodingKey.self, forKey: key)
        let xComposeKeys = Set(xCompose.allKeys.map(\.stringValue))
        guard xComposeKeys.contains("network") else {
            for nestedKey in xCompose.allKeys where nestedKey.stringValue != "network" {
                fputs(
                    "warning: networks: x-compose key '\(nestedKey.stringValue)' "
                        + "on '\(networkName)' isn't supported yet\n",
                    stderr
                )
            }
            return .nat
        }
        let networkKey = ComposeSerializeCodingKey(stringValue: "network")!
        let network = try xCompose.nestedContainer(keyedBy: ComposeSerializeCodingKey.self, forKey: networkKey)
        for nestedKey in network.allKeys {
            guard nestedKey.stringValue == "mode" else {
                fputs(
                    "warning: networks: x-compose.network key '\(nestedKey.stringValue)' "
                        + "on '\(networkName)' isn't supported yet\n",
                    stderr
                )
                continue
            }
            let raw = try network.decode(String.self, forKey: nestedKey)
            return try NetworkAttachmentMode.parse(raw)
        }
        return .nat
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
