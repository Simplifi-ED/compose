import Foundation

enum ComposeFileMerge {
    static func merge(_ files: [ComposeFile]) -> ComposeFile {
        precondition(!files.isEmpty, "merge requires at least one compose file")
        return files.dropFirst().reduce(files[0], merge(base:override:))
    }

    static func merge(base: ComposeFile, override: ComposeFile) -> ComposeFile {
        var mergedServices = base.services
        for (serviceName, overrideService) in override.services {
            if let baseService = mergedServices[serviceName] {
                mergedServices[serviceName] = merge(base: baseService, override: overrideService)
            } else {
                mergedServices[serviceName] = overrideService
            }
        }

        return ComposeFile(
            name: override.name ?? base.name,
            services: mergedServices
        )
    }

    static func merge(base: ComposeService, override: ComposeService) -> ComposeService {
        ComposeService(
            image: override.image ?? base.image,
            command: override.command ?? base.command,
            ports: ComposeBindingKeys.mergeUniqueEntries(
                base: base.ports,
                override: override.ports,
                key: ComposeBindingKeys.portMergeKey
            ),
            volumes: ComposeBindingKeys.mergeUniqueEntries(
                base: base.volumes,
                override: override.volumes,
                key: ComposeBindingKeys.volumeMergeKey
            ),
            environment: merge(base: base.environment, override: override.environment),
            containerName: override.containerName ?? base.containerName,
            dependsOn: mergeDependsOn(base: base.dependsOn, override: override.dependsOn),
            profiles: override.profiles.isEmpty ? base.profiles : override.profiles,
            deploy: merge(base: base.deploy, override: override.deploy),
            healthcheck: override.healthcheck ?? base.healthcheck
        )
    }

    static func mergeDependsOn(
        base: [ComposeDependency],
        override: [ComposeDependency]
    ) -> [ComposeDependency] {
        var byService: [String: ComposeDependency] = [:]
        var order: [String] = []

        for dependency in base {
            if byService[dependency.service] == nil {
                order.append(dependency.service)
            }
            byService[dependency.service] = dependency
        }
        for dependency in override {
            if byService[dependency.service] == nil {
                order.append(dependency.service)
            }
            byService[dependency.service] = dependency
        }
        return order.map { byService[$0]! }
    }

    static func merge(
        base: ComposeDeploy?,
        override: ComposeDeploy?
    ) -> ComposeDeploy? {
        switch (base, override) {
        case (nil, nil):
            return nil
        case (let base?, nil):
            return base
        case (nil, let override?):
            return override
        case (let base?, let override?):
            return ComposeDeploy(replicas: override.replicas ?? base.replicas)
        }
    }

    static func merge(
        base: ComposeEnvironment?,
        override: ComposeEnvironment?
    ) -> ComposeEnvironment? {
        switch (base, override) {
        case (nil, nil):
            return nil
        case (nil, let override?):
            return override
        case (let base?, nil):
            return base
        case (.map(let baseMap), .map(let overrideMap)):
            return .map(baseMap.merging(overrideMap) { _, override in override })
        case (.list(let baseList), .list(let overrideList)):
            return .list(
                ComposeBindingKeys.mergeUniqueEntries(
                    base: baseList,
                    override: overrideList,
                    key: { ComposeBindingKeys.environmentListEntryKey(for: $0) }
                )
            )
        // Map vs list: later file's entire environment form wins.
        case (_, let override?):
            return override
        }
    }
}
