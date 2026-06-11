import Foundation

/// Service-level `configs:` / `secrets:` reference.
public struct ComposeServiceMount: Sendable, Equatable {
    public let source: String
    public let target: String?

    public init(source: String, target: String? = nil) {
        self.source = source
        self.target = target
    }

    package func resolvedTarget(kind: ComposeFileMountKind) -> String {
        kind.resolvedTarget(sourceName: source, explicitTarget: target)
    }
}

enum ComposeServiceMountDecoder {
    static func decodeShortSyntax(_ value: String, kind: ComposeFileMountKind) throws -> ComposeServiceMount {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ComposeError.invalidField(kind.rootFieldName, reason: "entry must not be empty")
        }
        let parts = trimmed.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        switch parts.count {
        case 1:
            return ComposeServiceMount(source: String(parts[0]))
        case 2:
            let source = String(parts[0])
            let target = String(parts[1])
            guard !source.isEmpty else {
                throw ComposeError.invalidField(kind.rootFieldName, reason: "source name must not be empty")
            }
            return ComposeServiceMount(source: source, target: target.isEmpty ? nil : target)
        default:
            throw ComposeError.invalidField(kind.rootFieldName, reason: "invalid entry '\(value)'")
        }
    }

    static func mergeKey(for mount: ComposeServiceMount) -> String {
        mount.source
    }
}

struct ComposeServiceMountEntry: Decodable {
    let source: String
    let target: String?

    private enum CodingKeys: String, CodingKey {
        case source
        case target
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = try container.decode(String.self, forKey: .source)
        target = try container.decodeIfPresent(String.self, forKey: .target)
    }
}

extension ComposeServiceMount: Encodable {
    public func encode(to encoder: Encoder) throws {
        if let target, !target.isEmpty {
            var container = encoder.container(keyedBy: LongCodingKeys.self)
            try container.encode(source, forKey: .source)
            try container.encode(target, forKey: .target)
        } else {
            var container = encoder.singleValueContainer()
            try container.encode(source)
        }
    }

    private enum LongCodingKeys: String, CodingKey {
        case source
        case target
    }

    func encodeResolved(kind: ComposeFileMountKind, to encoder: Encoder) throws {
        let resolved = resolvedTarget(kind: kind)
        let defaultTarget = kind.defaultTarget(for: source)
        if resolved == defaultTarget, target == nil {
            var container = encoder.singleValueContainer()
            try container.encode(source)
        } else {
            var container = encoder.container(keyedBy: LongCodingKeys.self)
            try container.encode(source, forKey: .source)
            try container.encode(resolved, forKey: .target)
        }
    }
}
