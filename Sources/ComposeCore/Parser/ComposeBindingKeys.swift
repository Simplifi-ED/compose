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

    package static func portMergeKey(for port: String) -> String? {
        parsePortSpec(port)?.mergeKey
    }

    package static func volumeMergeKey(for volume: String) -> String? {
        let trimmed = volume.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }

        let containerPath = String(parts[1])
        guard !containerPath.isEmpty, containerPath.hasPrefix("/") else { return nil }

        return containerPath
    }

    package static func environmentListEntryKey(for entry: String) -> String {
        if let separatorIndex = entry.firstIndex(of: "=") {
            return String(entry[..<separatorIndex])
        }
        return entry
    }

    package static func mergeUniqueEntries(
        base: [String],
        override: [String],
        key: (String) -> String?
    ) -> [String] {
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
}
