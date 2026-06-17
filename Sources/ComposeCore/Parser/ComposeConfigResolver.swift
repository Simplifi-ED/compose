import Foundation

/// Resolves compose files for `compose config` — parse, profile filter, and scale overrides.
public enum ComposeConfigResolver {
    public static func resolve(
        fileURLs: [URL],
        projectName: String? = nil,
        activeProfiles: Set<String>,
        scaleOverrides: [String: Int],
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> ComposeFile {
        let parsed = try ComposeParser.parse(fileURLs: fileURLs, processEnvironment: processEnvironment)
        let resolvedProjectName = try projectName ?? ProjectNameResolver.resolve(
            cliProjectName: nil,
            composeName: parsed.name,
            firstFileURL: fileURLs.first
        )
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

        let adjusted = try scaledActiveServices(
            activeServices,
            scaleOverrides: scaleOverrides
        )

        try ComposeFileMountResolver.validate(
            composeFile: parsed,
            activeServiceNames: Set(activeServices.keys)
        )

        let resolvedServices = try BuildImageResolver.withResolvedImages(
            projectName: resolvedProjectName,
            services: adjusted
        )

        let composeFile = ComposeFile(
            name: parsed.name,
            services: resolvedServices,
            configs: parsed.configs,
            secrets: parsed.secrets,
            networks: parsed.networks,
            volumes: parsed.volumes
        )
        emitHostDNSWarnings(composeFile: composeFile, activeServiceNames: activeServiceNames)
        return composeFile
    }

    package static func emitHostDNSWarnings(
        composeFile: ComposeFile,
        activeServiceNames: Set<String>
    ) {
        for warning in HostDNSPlanning.warnings(
            composeFile: composeFile,
            activeServiceNames: activeServiceNames
        ) {
            fputs("\(warning.message)\n", stderr)
        }
    }

    /// Resolves the compose file and returns YAML unless `quiet` requests validation only.
    public static func resolveOutput(
        fileURLs: [URL],
        projectName: String? = nil,
        activeProfiles: Set<String>,
        scaleOverrides: [String: Int],
        quiet: Bool = false,
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> String? {
        let composeFile = try resolve(
            fileURLs: fileURLs,
            projectName: projectName,
            activeProfiles: activeProfiles,
            scaleOverrides: scaleOverrides,
            processEnvironment: processEnvironment
        )
        // ponytail: limits validate in scaledActiveServices for every config resolve; GPU reservations
        // validate only on --quiet so non-quiet config can still emit the reservation block.
        if quiet {
            try validateRuntimeUnsupportedReservationsForQuietConfig(composeFile.services)
        }
        guard !quiet else { return nil }
        return try ComposeSerializer.yamlString(from: composeFile)
    }

    private static func scaledActiveServices(
        _ activeServices: [String: ComposeService],
        scaleOverrides: [String: Int]
    ) throws -> [String: ComposeService] {
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
            try DeployResourceLimitsPlanning.validateLimits(
                scaled.deploy?.resources?.limits
            )
            adjusted[serviceName] = scaled
        }
        return adjusted
    }

    private static func validateRuntimeUnsupportedReservationsForQuietConfig(
        _ services: [String: ComposeService]
    ) throws {
        for service in services.values {
            try DeployGPUPlanning.validateReservations(service.deploy?.resources?.reservations)
        }
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
