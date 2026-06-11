import Foundation

public enum ServicePlanner {
    package struct PlanningContext: Sendable {
        package let composeFile: ComposeFile
        package let projectName: String
        package let composeDirectory: URL

        package init(composeFile: ComposeFile, projectName: String, composeDirectory: URL) {
            self.composeFile = composeFile
            self.projectName = projectName
            self.composeDirectory = composeDirectory
        }
    }

    public static func plans(
        for composeFile: ComposeFile,
        projectName: String,
        composeDirectory: URL,
        activeProfiles: Set<String> = [],
        scaleOverrides: [String: Int] = [:]
    ) throws -> [ServicePlan] {
        try startupLayers(
            for: composeFile,
            projectName: projectName,
            composeDirectory: composeDirectory,
            activeProfiles: activeProfiles,
            scaleOverrides: scaleOverrides
        ).flatMap { $0 }
    }

    public static func startupLayers(
        for composeFile: ComposeFile,
        projectName: String,
        composeDirectory: URL,
        activeProfiles: Set<String> = [],
        scaleOverrides: [String: Int] = [:]
    ) throws -> [[ServicePlan]] {
        try ComposeFileMountResolver.validate(composeFile: composeFile)
        let layers = try dependencyLayers(for: composeFile, activeProfiles: activeProfiles)
        try ReplicaPlanning.validateScaleTargets(
            scaleOverrides: scaleOverrides,
            services: composeFile.services,
            activeServiceNames: Set(layers.flatMap { $0.map(\.serviceName) })
        )
        return try layers.map { layer in
            try layer.flatMap { serviceName, service in
                let replicas = try ReplicaPlanning.resolvedReplicaCount(
                    serviceName: serviceName,
                    service: service,
                    scaleOverrides: scaleOverrides
                )
                try ReplicaPlanning.validateForUp(
                    serviceName: serviceName,
                    service: service,
                    replicas: replicas
                )
                return try (1...replicas).map { index in
                    try buildUpPlan(
                        context: PlanningContext(
                            composeFile: composeFile,
                            projectName: projectName,
                            composeDirectory: composeDirectory
                        ),
                        serviceName: serviceName,
                        service: service,
                        replicaIndex: index
                    )
                }
            }
        }
    }

    static func dependencyLayers(
        for composeFile: ComposeFile,
        activeProfiles: Set<String> = []
    ) throws -> [[(serviceName: String, service: ComposeService)]] {
        let services = try ProfileFilter.activeServices(
            from: composeFile.services,
            activeProfiles: activeProfiles
        )
        return try DependencyGraph.serviceLayers(for: services).map { layer in
            layer.map { ($0, services[$0]!) }
        }
    }

    static func shutdownLayers(
        for composeFile: ComposeFile,
        discoveredServiceNames: Set<String>
    ) throws -> [[String]] {
        try DependencyGraph.serviceLayers(for: composeFile.services)
            .reversed()
            .map { layer in layer.filter { discoveredServiceNames.contains($0) } }
            .filter { !$0.isEmpty }
    }

    public static func shutdownContainerLayers(
        for composeFile: ComposeFile,
        containers: [DiscoveredContainer]
    ) throws -> [[DiscoveredContainer]] {
        let byService = Dictionary(grouping: containers.compactMap { container -> (String, DiscoveredContainer)? in
            guard let serviceName = container.serviceName else { return nil }
            return (serviceName, container)
        }) { $0.0 }
            .mapValues { pairs in pairs.map(\.1) }
        let discoveredServiceNames = Set(byService.keys)
        let serviceLayers = try shutdownLayers(
            for: composeFile,
            discoveredServiceNames: discoveredServiceNames
        )

        var layers = serviceLayers.map { layer in
            layer.flatMap { byService[$0, default: []] }
        }

        let orphans = unmappedContainers(in: containers, composeFile: composeFile)
        if !orphans.isEmpty {
            layers.append(orphans)
        }

        return layers
    }

    /// Ordered shutdown waves when a compose file is present; parallel fallback otherwise.
    package static func shutdownLayers(
        for composeFile: ComposeFile?,
        containers: [DiscoveredContainer]
    ) throws -> [[DiscoveredContainer]] {
        guard let composeFile else {
            return [containers]
        }
        return try shutdownContainerLayers(for: composeFile, containers: containers)
    }

    static func unmappedContainers(
        in containers: [DiscoveredContainer],
        composeFile: ComposeFile
    ) -> [DiscoveredContainer] {
        OrphanRemoval.orphans(in: containers, composeFile: composeFile, policy: .yamlOnly)
    }

    /// Base name for one-off `run` containers; `up` uses `ReplicaPlanning.indexedContainerName`.
    public static func runContainerBaseName(
        serviceName: String,
        service: ComposeService,
        projectName: String
    ) -> String {
        if let containerName = service.containerName, !containerName.isEmpty {
            return containerName
        }
        return "\(projectName)_\(serviceName)"
    }

    public static func publishFlag(for port: String) throws -> String? {
        try ServiceRunMapping.publishFlag(for: port)
    }

    public static func volumeFlag(for volume: String, relativeTo composeDirectory: URL) throws -> String {
        try ServiceRunMapping.volumeFlag(for: volume, relativeTo: composeDirectory)
    }
}
