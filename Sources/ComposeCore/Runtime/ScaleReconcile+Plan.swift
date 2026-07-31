import Foundation

extension ScaleReconcile {
    package struct PlanningInput: Sendable {
        package let composeFile: ComposeFile
        package let projectName: String
        package let composeDirectory: URL
        package let scaleOverrides: [String: Int]
        package let containers: [ProjectContainer]
        package let activeProfiles: Set<String>
        package let machineName: String?
        package let requireAgentReachability: Bool

        package init(
            composeFile: ComposeFile,
            projectName: String,
            composeDirectory: URL,
            scaleOverrides: [String: Int],
            containers: [ProjectContainer],
            activeProfiles: Set<String>,
            machineName: String?,
            requireAgentReachability: Bool = true
        ) {
            self.composeFile = composeFile
            self.projectName = projectName
            self.composeDirectory = composeDirectory
            self.scaleOverrides = scaleOverrides
            self.containers = containers
            self.activeProfiles = activeProfiles
            self.machineName = machineName
            self.requireAgentReachability = requireAgentReachability
        }
    }

    package static func plan(_ input: PlanningInput) throws -> Plan {
        guard !input.scaleOverrides.isEmpty else {
            throw ComposeError.scaleRequiresTargets
        }
        let activeServices = try ProfileFilter.activeServices(
            from: input.composeFile.services,
            activeProfiles: input.activeProfiles
        )
        try ServicePlanner.validateStartupPlanning(
            composeFile: input.composeFile,
            activeServiceNames: Set(activeServices.keys),
            machineName: input.machineName,
            scaleOverrides: input.scaleOverrides,
            requireAgentReachability: input.requireAgentReachability
        )
        let context = ServicePlanner.PlanningContext(
            composeFile: input.composeFile,
            projectName: input.projectName,
            composeDirectory: input.composeDirectory,
            machineName: input.machineName,
            requireAgentReachability: input.requireAgentReachability
        )
        var toStart: [ServicePlan] = []
        var toStop: [String] = []
        for serviceName in input.scaleOverrides.keys.sorted() {
            guard let service = activeServices[serviceName] else { continue }
            try planService(
                ServiceDeltaInput(
                    serviceName: serviceName,
                    service: service,
                    desired: input.scaleOverrides[serviceName]!,
                    planningInput: input,
                    context: context
                ),
                toStart: &toStart,
                toStop: &toStop
            )
        }
        toStop.sort { trailingReplicaIndex($0) > trailingReplicaIndex($1) }
        return Plan(toStart: toStart, toStop: toStop)
    }

    private static func trailingReplicaIndex(_ containerName: String) -> Int {
        guard let last = containerName.split(separator: "_").last,
              let value = Int(last)
        else { return 0 }
        return value
    }

    private struct ServiceDeltaInput: Sendable {
        let serviceName: String
        let service: ComposeService
        let desired: Int
        let planningInput: PlanningInput
        let context: ServicePlanner.PlanningContext
    }

    private static func planService(
        _ input: ServiceDeltaInput,
        toStart: inout [ServicePlan],
        toStop: inout [String]
    ) throws {
        try ReplicaPlanning.validateForUp(
            serviceName: input.serviceName,
            service: input.service,
            replicas: input.desired
        )
        let serviceContainers = input.planningInput.containers.filter {
            $0.serviceName == input.serviceName
        }
        let runningIndices = Set(
            serviceContainers
                .filter { $0.status == .running }
                .compactMap {
                    ReplicaPlanning.replicaIndex(
                        projectName: input.planningInput.projectName,
                        serviceName: input.serviceName,
                        containerName: $0.name
                    )
                }
        )
        for index in 1...input.desired where !runningIndices.contains(index) {
            toStart.append(
                try ServicePlanner.buildUpPlan(
                    context: input.context,
                    serviceName: input.serviceName,
                    service: input.service,
                    replicaIndex: index
                )
            )
        }
        for container in serviceContainers {
            guard let index = ReplicaPlanning.replicaIndex(
                projectName: input.planningInput.projectName,
                serviceName: input.serviceName,
                containerName: container.name
            ) else { continue }
            if index > input.desired {
                toStop.append(container.name)
            }
        }
    }
}
