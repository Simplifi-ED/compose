import Foundation

package enum WatchSession {
    package struct WatchedService: Sendable {
        package let serviceName: String
        package let rules: [ResolvedWatchRule]
        package let plans: [ServicePlan]
        package let containers: [ProjectContainer]
    }

    package struct Configuration: Sendable {
        package let projectName: String
        package let composeDirectory: URL
        package let services: [WatchedService]
    }

    package struct Dependencies: Sendable {
        package let projectName: String
        package var copyIn: ContainerFileSync.CopyIn
        package var getContainer: ContainerFileSync.GetContainer
        package var listProjectContainers: @Sendable () async throws -> [ProjectContainer]
        package var restartPlans: @Sendable ([ServicePlan]) async throws -> Void

        package init(
            projectName: String,
            copyIn: @escaping ContainerFileSync.CopyIn = ContainerCopyAPI.copyIn,
            getContainer: @escaping ContainerFileSync.GetContainer = ContainerCopyAPI.get,
            listProjectContainers: (@Sendable () async throws -> [ProjectContainer])? = nil,
            restartPlans: @escaping @Sendable ([ServicePlan]) async throws -> Void = { plans in
                try await ServiceRunnerRestart.restartPlans(plans)
            }
        ) {
            self.projectName = projectName
            self.copyIn = copyIn
            self.getContainer = getContainer
            self.listProjectContainers = listProjectContainers ?? {
                try await ContainerDiscovery.projectContainers(forProject: projectName)
            }
            self.restartPlans = restartPlans
        }
    }

    package static func run(
        configuration: Configuration,
        dependencies: Dependencies
    ) async throws {
        let eventBuffer = WatchEventBuffer()
        let runtimes = makeRuntimes(configuration: configuration, dependencies: dependencies)
        try await runInitialSync(
            configuration: configuration,
            runtimes: runtimes,
            dependencies: dependencies
        )

        let ruleLookup = Dictionary(
            uniqueKeysWithValues: configuration.services.flatMap { service in
                service.rules.map { ($0.ruleID, (service.serviceName, $0)) }
            }
        )

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await debounceLoop(
                    projectName: configuration.projectName,
                    ruleLookup: ruleLookup,
                    runtimes: runtimes,
                    dependencies: dependencies,
                    eventBuffer: eventBuffer
                )
            }

            for service in configuration.services {
                for rule in service.rules {
                    let monitor = FileWatchMonitor(resolved: rule)
                    group.addTask {
                        for await event in monitor.events() {
                            try Task.checkCancellation()
                            await eventBuffer.schedule(
                                ruleID: rule.ruleID,
                                hostPath: event.hostPath
                            )
                        }
                    }
                }
            }

            try await group.waitForAll()
        }
    }

    private static func debounceLoop(
        projectName: String,
        ruleLookup: [String: (String, ResolvedWatchRule)],
        runtimes: [String: WatchServiceRuntime],
        dependencies: Dependencies,
        eventBuffer: WatchEventBuffer
    ) async throws {
        var debouncer = WatchDebouncer()
        let clock = ContinuousClock()
        while !Task.isCancelled {
            let now = clock.now
            _ = await eventBuffer.drainInto(debouncer: &debouncer, at: now)
            let ready = debouncer.drainReady(at: now)
            for change in ready {
                guard let (serviceName, rule) = ruleLookup[change.ruleID],
                      let runtime = runtimes[serviceName] else { continue }
                try await applyChange(
                    runtime: runtime,
                    rule: rule,
                    hostPath: change.hostPath,
                    projectName: projectName,
                    dependencies: dependencies
                )
            }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    private static func applyChange(
        runtime: WatchServiceRuntime,
        rule: ResolvedWatchRule,
        hostPath: URL,
        projectName: String,
        dependencies: Dependencies
    ) async throws {
        try await runtime.refreshContainers()
        let containers = await runtime.runningContainers()

        try await ContainerFileSync.sync(
            resolved: rule,
            hostPath: hostPath,
            containers: containers,
            projectName: projectName,
            copyIn: dependencies.copyIn,
            getContainer: dependencies.getContainer
        )
        guard rule.rule.action == .syncRestart else { return }

        let plansToRestart: [ServicePlan]
        do {
            plansToRestart = try await runtime.plansMatchingRunning()
        } catch {
            try? await runtime.refreshContainers()
            throw error
        }

        fputs("Restarting \(rule.serviceName) after sync\n", stderr)
        do {
            try await dependencies.restartPlans(plansToRestart)
            try await runtime.waitForRunning(containerNames: plansToRestart.map(\.name))
        } catch {
            try? await runtime.refreshContainers()
            throw error
        }

        // Recreate tears down the container filesystem; copy synced content back in.
        try await ContainerFileSync.sync(
            resolved: rule,
            hostPath: hostPath,
            containers: await runtime.runningContainers(),
            projectName: projectName,
            copyIn: dependencies.copyIn,
            getContainer: dependencies.getContainer
        )
    }
}

/// Thread-safe buffer between FSEvent callbacks and the debounce loop.
package actor WatchEventBuffer {
    private var pending: [(ruleID: String, hostPath: URL)] = []

    package func schedule(ruleID: String, hostPath: URL) {
        pending.append((ruleID, hostPath))
    }

    package func drainInto(debouncer: inout WatchDebouncer, at now: ContinuousClock.Instant) -> Int {
        let batch = pending
        pending = []
        for item in batch {
            debouncer.schedule(ruleID: item.ruleID, hostPath: item.hostPath, at: now)
        }
        return batch.count
    }
}
