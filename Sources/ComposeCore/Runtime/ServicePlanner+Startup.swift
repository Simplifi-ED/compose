import Foundation

extension ServicePlanner {
    static func validateStartupPlanning(
        composeFile: ComposeFile,
        activeServiceNames: Set<String>,
        machineName: String?,
        scaleOverrides: [String: Int],
        requireAgentReachability: Bool = true
    ) throws {
        try ComposeFileMountResolver.validate(
            composeFile: composeFile,
            activeServiceNames: activeServiceNames
        )
        try NetworkPlanning.validate(
            composeFile: composeFile,
            activeServiceNames: activeServiceNames,
            machineName: machineName
        )
        try VolumePlanning.validate(
            composeFile: composeFile,
            activeServiceNames: activeServiceNames
        )
        try PlatformPlanning.validate(
            services: composeFile.services,
            activeServiceNames: activeServiceNames,
            machineName: machineName
        )
        try ReplicaPlanning.validateScaleTargets(
            scaleOverrides: scaleOverrides,
            services: composeFile.services,
            activeServiceNames: activeServiceNames
        )
        try SSHAgentForwarding.validateStartup(
            services: composeFile.services,
            activeServiceNames: activeServiceNames,
            requireAgentReachability: requireAgentReachability
        )
    }

    static func buildStartupLayerPlans(
        layers: [[(serviceName: String, service: ComposeService)]],
        context: PlanningContext,
        scaleOverrides: [String: Int]
    ) throws -> [[ServicePlan]] {
        try layers.map { layer in
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
                        context: context,
                        serviceName: serviceName,
                        service: service,
                        replicaIndex: index
                    )
                }
            }
        }
    }
}
