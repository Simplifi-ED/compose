import Foundation

/// Per-service mutable watch state: refreshed container discovery and serialized apply.
package actor WatchServiceRuntime {
    private var containers: [ProjectContainer]
    package let serviceName: String
    package let plans: [ServicePlan]
    private let listContainers: @Sendable () async throws -> [ProjectContainer]
    private let getContainer: ContainerFileSync.GetContainer

    package init(
        serviceName: String,
        plans: [ServicePlan],
        containers: [ProjectContainer],
        listContainers: @escaping @Sendable () async throws -> [ProjectContainer],
        getContainer: @escaping ContainerFileSync.GetContainer
    ) {
        self.serviceName = serviceName
        self.plans = plans
        self.containers = containers
        self.listContainers = listContainers
        self.getContainer = getContainer
    }

    package func refreshContainers() async throws {
        let all = try await listContainers()
        containers = all.filter { $0.serviceName == serviceName }
    }

    package func runningContainers() -> [ProjectContainer] {
        containers.filter { $0.status == .running }
    }

    /// Running containers must exactly match pre-built restart plans (same names).
    package func plansMatchingRunning() throws -> [ServicePlan] {
        let running = runningContainers()
        guard !running.isEmpty else {
            throw ComposeError.serviceNotRunning(
                service: serviceName,
                state: containers.isEmpty ? "not started" : "not running"
            )
        }

        let runningNames = Set(running.map(\.name))
        let matched = plans.filter { runningNames.contains($0.name) }
        let planNames = Set(plans.map(\.name))

        let unmatchedRunning = runningNames.subtracting(planNames)
        if !unmatchedRunning.isEmpty {
            throw ComposeError.invalidField(
                "develop.watch",
                reason: "running container(s) \(Self.sortedList(unmatchedRunning)) for service "
                    + "'\(serviceName)' have no restart plan; run compose up to align replicas, "
                    + "then re-run compose watch"
            )
        }

        let unmatchedPlans = planNames.subtracting(runningNames)
        if !unmatchedPlans.isEmpty {
            throw ComposeError.invalidField(
                "develop.watch",
                reason: "restart plan(s) \(Self.sortedList(unmatchedPlans)) for service "
                    + "'\(serviceName)' are not running; run compose up to align replicas, "
                    + "then re-run compose watch"
            )
        }

        return matched
    }

    package func waitForRunning(containerNames: [String], timeout: Duration = .seconds(60)) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        let pollInterval: Duration = .milliseconds(250)

        while clock.now < deadline {
            try Task.checkCancellation()
            var allRunning = true
            for name in containerNames {
                let snapshot = try await getContainer(name)
                if snapshot.status != .running {
                    allRunning = false
                    break
                }
            }
            if allRunning {
                try await refreshContainers()
                return
            }
            try await Task.sleep(for: pollInterval)
        }

        throw ComposeError.serviceNotRunning(
            service: serviceName,
            state: "not running within \(timeout)"
        )
    }

    private static func sortedList(_ names: Set<String>) -> String {
        names.sorted().joined(separator: ", ")
    }
}
