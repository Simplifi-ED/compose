import Foundation

/// Delta replica reconcile for `compose scale` — start missing indices, stop excess; no teardown within desired count.
package enum ScaleReconcile {
    package struct Plan: Sendable {
        package let toStart: [ServicePlan]
        package let toStop: [String]

        package init(toStart: [ServicePlan], toStop: [String]) {
            self.toStart = toStart
            self.toStop = toStop
        }
    }

    package static func plan(
        composeFile: ComposeFile,
        projectName: String,
        composeDirectory: URL,
        scaleOverrides: [String: Int],
        containers: [ProjectContainer],
        activeProfiles: Set<String>,
        machineName: String?,
        requireAgentReachability: Bool = true
    ) throws -> Plan {
        guard !scaleOverrides.isEmpty else {
            throw ComposeError.scaleRequiresTargets
        }
        let activeServices = try ProfileFilter.activeServices(
            from: composeFile.services,
            activeProfiles: activeProfiles
        )
        let activeServiceNames = Set(activeServices.keys)
        try ServicePlanner.validateStartupPlanning(
            composeFile: composeFile,
            activeServiceNames: activeServiceNames,
            machineName: machineName,
            scaleOverrides: scaleOverrides,
            requireAgentReachability: requireAgentReachability
        )
        let context = ServicePlanner.PlanningContext(
            composeFile: composeFile,
            projectName: projectName,
            composeDirectory: composeDirectory,
            machineName: machineName,
            requireAgentReachability: requireAgentReachability
        )
        var toStart: [ServicePlan] = []
        var toStop: [String] = []
        for serviceName in scaleOverrides.keys.sorted() {
            guard let service = activeServices[serviceName] else { continue }
            let desired = scaleOverrides[serviceName]!
            try ReplicaPlanning.validateForUp(
                serviceName: serviceName,
                service: service,
                replicas: desired
            )
            let serviceContainers = containers.filter { $0.serviceName == serviceName }
            let runningIndices = Set(
                serviceContainers
                    .filter { $0.status == .running }
                    .compactMap {
                        ReplicaPlanning.replicaIndex(
                            projectName: projectName,
                            serviceName: serviceName,
                            containerName: $0.name
                        )
                    }
            )
            for index in 1...desired where !runningIndices.contains(index) {
                toStart.append(
                    try ServicePlanner.buildUpPlan(
                        context: context,
                        serviceName: serviceName,
                        service: service,
                        replicaIndex: index
                    )
                )
            }
            for container in serviceContainers {
                guard let index = ReplicaPlanning.replicaIndex(
                    projectName: projectName,
                    serviceName: serviceName,
                    containerName: container.name
                ) else { continue }
                if index > desired {
                    toStop.append(container.name)
                }
            }
        }
        toStop.sort { lhs, rhs in
            trailingReplicaIndex(lhs) > trailingReplicaIndex(rhs)
        }
        return Plan(toStart: toStart, toStop: toStop)
    }

    private static func trailingReplicaIndex(_ containerName: String) -> Int {
        guard let last = containerName.split(separator: "_").last,
              let value = Int(last)
        else { return 0 }
        return value
    }

    package static func execute(
        plan: Plan,
        projectName: String,
        imagePullOutput: ImagePullOutput?,
        machineContext: MachineContext,
        maxConcurrent: Int? = nil
    ) async throws -> [String] {
        let policy = WaveExecutionPolicy(maxConcurrent: maxConcurrent)
        var affected: [String] = []
        if !plan.toStop.isEmpty {
            let stopResult = await ServiceRunner.parallelRun(
                plan.toStop.map {
                    ServiceRunner.ParallelRunItem(label: $0, collectOnSuccess: $0, value: $0)
                },
                maxConcurrent: policy.maxConcurrent
            ) { name in
                ComposeFileStaging.removeContainerStaging(
                    projectName: projectName,
                    containerName: name
                )
                try await ContainerTeardown.teardown(id: name, machineContext: machineContext)
            }
            if !stopResult.failures.isEmpty {
                throw ComposeError.multipleServiceFailures(stopResult.failures)
            }
            affected.append(contentsOf: stopResult.succeeded)
        }
        if plan.toStart.isEmpty {
            return affected
        }
        let hostPullOutput = machineContext.isMachineMode ? nil : imagePullOutput
        if let hostPullOutput {
            try await ImagePullRunner.pullMissing(
                plans: plan.toStart,
                output: hostPullOutput,
                maxConcurrent: policy.maxConcurrent
            )
        }
        let startResult = await ServiceRunner.parallelRun(
            plan.toStart.map {
                ServiceRunner.ParallelRunItem(label: $0.name, collectOnSuccess: $0.name, value: $0)
            },
            maxConcurrent: policy.maxConcurrent
        ) { servicePlan in
            try await ServiceRunner.runContainerWithFileMounts(
                servicePlan,
                imagePullOutput: hostPullOutput,
                machineContext: machineContext
            )
        }
        if !startResult.failures.isEmpty {
            throw ComposeError.multipleServiceFailures(startResult.failures)
        }
        affected.append(contentsOf: startResult.succeeded)
        return affected
    }
}
