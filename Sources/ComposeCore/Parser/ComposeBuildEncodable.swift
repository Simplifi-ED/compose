import Foundation

extension ComposeBuild: Encodable {
    private enum CodingKeys: String, CodingKey {
        case context
        case dockerfile
        case args
        case target
        case ssh
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(context, forKey: .context)
        try container.encodeIfPresent(dockerfile, forKey: .dockerfile)
        if !args.isEmpty {
            var argsContainer = container.nestedContainer(keyedBy: ComposeSerializeCodingKey.self, forKey: .args)
            for key in args.keys.sorted() {
                try argsContainer.encode(args[key]!, forKey: ComposeSerializeCodingKey(stringValue: key)!)
            }
        }
        try container.encodeIfPresent(target, forKey: .target)
        if !ssh.isEmpty {
            try container.encode(ssh, forKey: .ssh)
        }
    }
}
