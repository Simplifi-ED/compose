import Foundation

enum ComposeIncludeResourceMerge {
    static func merge(
        into model: inout ComposeFile,
        included: ComposeFile,
        includePath: String,
        definedIn: String
    ) throws {
        var configs = model.configs
        var secrets = model.secrets
        for kind in ComposeFileMountKind.allCases {
            switch kind {
            case .config:
                try mergeResources(
                    into: &configs,
                    from: included.configs,
                    kind: kind,
                    includePath: includePath,
                    definedIn: definedIn
                )
            case .secret:
                try mergeResources(
                    into: &secrets,
                    from: included.secrets,
                    kind: kind,
                    includePath: includePath,
                    definedIn: definedIn
                )
            }
        }
        let networks = try mergeNetworks(
            into: model.networks,
            from: included.networks,
            includePath: includePath,
            definedIn: definedIn
        )
        let volumes = try mergeVolumes(
            into: model.volumes,
            from: included.volumes,
            includePath: includePath,
            definedIn: definedIn
        )
        model = ComposeFile(
            name: model.name,
            services: model.services,
            configs: configs,
            secrets: secrets,
            networks: networks,
            volumes: volumes
        )
    }

    private static func mergeNetworks(
        into target: [String: ComposeNetwork],
        from included: [String: ComposeNetwork],
        includePath: String,
        definedIn: String
    ) throws -> [String: ComposeNetwork] {
        var merged = target
        for (name, network) in included {
            if merged[name] != nil {
                throw ComposeError.includeNetworkConflict(
                    name: name,
                    includePath: includePath,
                    definedIn: definedIn
                )
            }
            merged[name] = network
        }
        return merged
    }

    private static func mergeVolumes(
        into target: [String: ComposeVolume],
        from included: [String: ComposeVolume],
        includePath: String,
        definedIn: String
    ) throws -> [String: ComposeVolume] {
        var merged = target
        for (name, volume) in included {
            if merged[name] != nil {
                throw ComposeError.includeVolumeConflict(
                    name: name,
                    includePath: includePath,
                    definedIn: definedIn
                )
            }
            merged[name] = volume
        }
        return merged
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
