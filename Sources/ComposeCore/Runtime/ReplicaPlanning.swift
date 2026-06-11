import Foundation

/// Pure validation and naming helpers for replica expansion.
///
/// Replica loops live in `ServicePlanner`; this module never calls back into it.
enum ReplicaPlanning {
    /// CLI `--scale` wins over `deploy.replicas`; the default is one replica.
    static func resolvedReplicaCount(
        serviceName: String,
        service: ComposeService,
        scaleOverrides: [String: Int]
    ) throws -> Int {
        let count = scaleOverrides[serviceName] ?? service.deploy?.replicas ?? 1
        guard count >= 1 else {
            throw ComposeError.replicasBelowMinimum(service: serviceName, count: count)
        }
        return count
    }

    /// Rejects `--scale` targets that don't exist or are excluded by inactive profiles.
    static func validateScaleTargets(
        scaleOverrides: [String: Int],
        services: [String: ComposeService],
        activeServiceNames: Set<String>
    ) throws {
        for serviceName in scaleOverrides.keys.sorted() {
            guard let service = services[serviceName] else {
                throw ComposeError.undefinedService(service: serviceName)
            }
            guard activeServiceNames.contains(serviceName) else {
                throw ComposeError.scaleServiceRequiresProfile(
                    service: serviceName,
                    requiredProfiles: service.profiles
                )
            }
        }
    }

    /// Single front door for `up` planning constraints before building any replica plan.
    static func validateForUp(
        serviceName: String,
        service: ComposeService,
        replicas: Int
    ) throws {
        if let containerName = service.containerName, !containerName.isEmpty {
            throw ComposeError.containerNameNotSupportedWithReplicas(
                service: serviceName,
                containerName: containerName
            )
        }
        guard replicas > 1 else { return }
        for port in service.ports {
            guard let spec = ComposeBindingKeys.parsePortSpec(port) else {
                throw ComposeError.unsupportedPort(port)
            }
            if spec.hasStaticHostPort {
                throw ComposeError.staticPortBlocksScaling(
                    service: serviceName,
                    port: port,
                    replicas: replicas
                )
            }
        }
    }

    /// Uniform `{project}_{service}_{index}` naming, applied even at one replica.
    static func indexedContainerName(
        projectName: String,
        serviceName: String,
        index: Int
    ) -> String {
        "\(projectName)_\(serviceName)_\(index)"
    }
}
