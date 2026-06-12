import Foundation

/// Subset of the compose `build` block the plugin understands.
public struct ComposeBuild: Sendable, Equatable {
    public let context: String
    public let dockerfile: String?
    public let args: [String: String]
    public let target: String?

    public init(
        context: String,
        dockerfile: String? = nil,
        args: [String: String] = [:],
        target: String? = nil
    ) {
        self.context = context
        self.dockerfile = dockerfile
        self.args = args
        self.target = target
    }
}

extension ComposeBuild: Decodable {
    package static let supportedKeys: Set<String> = [
        "context", "dockerfile", "args", "target"
    ]

    private enum CodingKeys: String, CodingKey {
        case context
        case dockerfile
        case args
        case target
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        guard let context = try container.decodeIfPresent(String.self, forKey: .context) else {
            throw ComposeError.invalidField(
                "build.context",
                reason: "expected a path when build is a map (for example context: .)"
            )
        }
        guard !context.isEmpty else {
            throw ComposeError.invalidField("build.context", reason: "expected a non-empty path")
        }

        self.context = context
        dockerfile = try container.decodeIfPresent(String.self, forKey: .dockerfile)
        args = try container.decodeIfPresent([String: String].self, forKey: .args) ?? [:]
        target = try container.decodeIfPresent(String.self, forKey: .target)
    }
}
