import Foundation

package enum ComposeBindingKeys {
    package struct PortSpec: Equatable, Sendable {
        /// Explicit host port; `nil` for container-only specs like `"80"` or `":80"`.
        package let hostPort: String?
        package let containerPort: String
        package let protocolSuffix: String

        package var hasStaticHostPort: Bool { hostPort != nil }

        package var mergeKey: String {
            "\(hostPort ?? ""):\(containerPort)\(protocolSuffix)"
        }
    }

    package struct VolumeSpec: Equatable, Sendable {
        package let hostPath: String
        package let containerPath: String
        package let options: [String]

        package init(hostPath: String, containerPath: String, options: [String]) {
            self.hostPath = hostPath
            self.containerPath = containerPath
            self.options = options
        }

        /// Container path only; mount options do not affect merge identity.
        package var mergeKey: String { containerPath }

        package func formattedMount(resolvedHostPath: String) -> String {
            guard !options.isEmpty else {
                return "\(resolvedHostPath):\(containerPath)"
            }
            return "\(resolvedHostPath):\(containerPath):\(options.joined(separator: ","))"
        }

        package static func readOnlyMount(resolvedHostPath: String, containerPath: String) -> String {
            VolumeSpec(hostPath: resolvedHostPath, containerPath: containerPath, options: ["ro"])
                .formattedMount(resolvedHostPath: resolvedHostPath)
        }
    }

    package static func parsePortSpec(_ port: String) -> PortSpec? {
        let trimmed = port.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let protocolSuffix: String
        let hostContainerPart: String
        if let slashIndex = trimmed.firstIndex(of: "/") {
            hostContainerPart = String(trimmed[..<slashIndex])
            protocolSuffix = String(trimmed[slashIndex...])
        } else {
            hostContainerPart = trimmed
            protocolSuffix = ""
        }

        let parts = hostContainerPart.split(separator: ":", omittingEmptySubsequences: false)
        switch parts.count {
        case 1 where Int(parts[0]) != nil:
            return PortSpec(
                hostPort: nil,
                containerPort: String(parts[0]),
                protocolSuffix: protocolSuffix
            )
        case 2 where parts[0].isEmpty && Int(parts[1]) != nil:
            return PortSpec(
                hostPort: nil,
                containerPort: String(parts[1]),
                protocolSuffix: protocolSuffix
            )
        case 2 where Int(parts[0]) != nil && Int(parts[1]) != nil:
            return PortSpec(
                hostPort: String(parts[0]),
                containerPort: String(parts[1]),
                protocolSuffix: protocolSuffix
            )
        default:
            return nil
        }
    }

    package static func parseVolumeSpec(_ volume: String) throws -> VolumeSpec {
        let trimmed = volume.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ComposeError.unsupportedVolume(volume)
        }

        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        let options: [String]
        switch parts.count {
        case 2:
            options = []
        case 3:
            options = try parseVolumeMountOptions(String(parts[2]), volume: volume)
        default:
            throw ComposeError.unsupportedVolume(volume)
        }

        let hostPath = String(parts[0])
        let containerPath = String(parts[1])

        guard !hostPath.isEmpty, !containerPath.isEmpty else {
            throw ComposeError.unsupportedVolume(volume)
        }
        guard containerPath.hasPrefix("/") else {
            throw ComposeError.unsupportedVolume(volume)
        }

        let isBindMountSource = hostPath.contains("/") || hostPath == "." || hostPath == ".."
        guard isBindMountSource else {
            throw ComposeError.unsupportedNamedVolume(volume)
        }

        return VolumeSpec(hostPath: hostPath, containerPath: containerPath, options: options)
    }

    package static func portMergeKey(for port: String) -> String? {
        parsePortSpec(port)?.mergeKey
    }

    package static func volumeMergeKey(for volume: String) -> String? {
        try? parseVolumeSpec(volume).mergeKey
    }

    package static func environmentListEntryKey(for entry: String) -> String {
        if let separatorIndex = entry.firstIndex(of: "=") {
            return String(entry[..<separatorIndex])
        }
        return entry
    }

    package static func mergeUniqueEntries<Element>(
        base: [Element],
        override: [Element],
        key: (Element) -> String?
    ) -> [Element] {
        var merged = base
        var indexByKey: [String: Int] = [:]
        for (index, entry) in base.enumerated() {
            if let entryKey = key(entry) {
                indexByKey[entryKey] = index
            }
        }

        for entry in override {
            guard let entryKey = key(entry) else {
                merged.append(entry)
                continue
            }
            if let existingIndex = indexByKey[entryKey] {
                merged[existingIndex] = entry
            } else {
                indexByKey[entryKey] = merged.count
                merged.append(entry)
            }
        }

        return merged
    }

    private static func parseVolumeMountOptions(_ raw: String, volume: String) throws -> [String] {
        let tokens = raw.split(separator: ",").map {
            String($0).trimmingCharacters(in: .whitespaces)
        }
        guard !tokens.isEmpty, tokens.allSatisfy({ !$0.isEmpty }) else {
            throw ComposeError.unsupportedVolumeOption(volume)
        }
        var seen = Set<String>()
        var normalized: [String] = []
        normalized.reserveCapacity(tokens.count)
        for token in tokens {
            let lower = token.lowercased()
            if lower == "rw" {
                throw ComposeError.unsupportedVolumeOption(volume)
            }
            guard lower == "ro" || lower == "z" else {
                throw ComposeError.unsupportedVolumeOption(volume)
            }
            guard seen.insert(lower).inserted else {
                throw ComposeError.unsupportedVolumeOption(volume)
            }
            normalized.append(lower)
        }
        return normalized
    }
}
