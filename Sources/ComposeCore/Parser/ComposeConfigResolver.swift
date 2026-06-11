import Foundation

/// Resolves compose files for `compose config` — parse, profile filter, and scale overrides.
public enum ComposeConfigResolver {
    public static func resolve(
        fileURLs: [URL],
        activeProfiles: Set<String>,
        scaleOverrides: [String: Int],
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> ComposeFile {
        let parsed = try ComposeParser.parse(fileURLs: fileURLs, processEnvironment: processEnvironment)
        let activeServices = try ProfileFilter.activeServices(
            from: parsed.services,
            activeProfiles: activeProfiles
        )
        let activeServiceNames = Set(activeServices.keys)
        try ReplicaPlanning.validateScaleTargets(
            scaleOverrides: scaleOverrides,
            services: parsed.services,
            activeServiceNames: activeServiceNames
        )

        var adjusted: [String: ComposeService] = [:]
        adjusted.reserveCapacity(activeServices.count)
        for (serviceName, service) in activeServices {
            let scaled = applyScale(
                to: service,
                serviceName: serviceName,
                scaleOverrides: scaleOverrides
            )
            let replicas = try ReplicaPlanning.resolvedReplicaCount(
                serviceName: serviceName,
                service: scaled,
                scaleOverrides: scaleOverrides
            )
            try ReplicaPlanning.validateForUp(
                serviceName: serviceName,
                service: scaled,
                replicas: replicas
            )
            adjusted[serviceName] = scaled
        }

        let resolved = ComposeFile(
            name: parsed.name,
            services: adjusted,
            configs: parsed.configs,
            secrets: parsed.secrets
        )
        return resolved
    }

    /// Resolves the compose file and returns YAML unless `quiet` requests validation only.
    public static func resolveOutput(
        fileURLs: [URL],
        activeProfiles: Set<String>,
        scaleOverrides: [String: Int],
        quiet: Bool = false,
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> String? {
        let composeFile = try resolve(
            fileURLs: fileURLs,
            activeProfiles: activeProfiles,
            scaleOverrides: scaleOverrides,
            processEnvironment: processEnvironment
        )
        guard !quiet else { return nil }
        return try ComposeSerializer.yamlString(from: composeFile)
    }

    private static func applyScale(
        to service: ComposeService,
        serviceName: String,
        scaleOverrides: [String: Int]
    ) -> ComposeService {
        guard let replicaCount = scaleOverrides[serviceName] else {
            return service
        }
        return service.withDeploy(replicas: replicaCount)
    }
}
