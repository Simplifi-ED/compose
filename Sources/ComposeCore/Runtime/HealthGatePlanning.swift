import Foundation

enum HealthGatePlanning {
    static func gatesForNextLayer(
        nextLayer: [ServicePlan],
        context: HealthWaitContext
    ) throws -> [HealthGate] {
        struct GateKey: Hashable {
            let service: String
            let condition: DependsOnCondition
        }

        var merged: [GateKey: Set<String>] = [:]

        for plan in nextLayer {
            guard let service = context.services[plan.serviceName] else {
                throw ComposeError.undefinedService(service: plan.serviceName)
            }
            for dependency in service.dependsOn where dependency.requiresReadinessWait {
                guard let dependencyService = context.services[dependency.service] else {
                    throw ComposeError.unknownDependency(
                        service: plan.serviceName,
                        dependency: dependency.service
                    )
                }
                let replicaCount = try ReplicaPlanning.resolvedReplicaCount(
                    serviceName: dependency.service,
                    service: dependencyService,
                    scaleOverrides: context.scaleOverrides
                )
                let containerNames = (1...replicaCount).map { index in
                    ReplicaPlanning.indexedContainerName(
                        projectName: context.projectName,
                        serviceName: dependency.service,
                        index: index
                    )
                }
                let key = GateKey(service: dependency.service, condition: dependency.condition)
                merged[key, default: []].formUnion(containerNames)
            }
        }

        return merged.map { key, containerNames in
            HealthGate(
                dependencyService: key.service,
                condition: key.condition,
                containerNames: containerNames.sorted()
            )
        }.sorted {
            $0.dependencyService == $1.dependencyService
                ? $0.condition.readinessSortOrder < $1.condition.readinessSortOrder
                : $0.dependencyService < $1.dependencyService
        }
    }
}
