import Foundation

enum ComposeIncludeResourceMerge {
    static func merge(
        into model: inout ComposeFile,
        included: ComposeFile,
        includePath: String,
        definedIn: String
    ) throws {
        var resourceMaps: [ComposeFileMountKind: [String: ComposeFileResource]] = [
            .config: model.configs,
            .secret: model.secrets
        ]
        for kind in ComposeFileMountKind.allCases {
            try mergeResources(
                into: &resourceMaps[kind]!,
                from: included.resources(for: kind),
                kind: kind,
                includePath: includePath,
                definedIn: definedIn
            )
        }
        model = ComposeFile(
            name: model.name,
            services: model.services,
            configs: resourceMaps[.config]!,
            secrets: resourceMaps[.secret]!
        )
    }

    private static func mergeResources(
        into target: inout [String: ComposeFileResource],
        from included: [String: ComposeFileResource],
        kind: ComposeFileMountKind,
        includePath: String,
        definedIn: String
    ) throws {
        for (name, resource) in included {
            if target[name] != nil {
                throw ComposeError.includeResourceConflict(
                    name: name,
                    kind: kind,
                    includePath: includePath,
                    definedIn: definedIn
                )
            }
            target[name] = resource
        }
    }
}
