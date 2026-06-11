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
        package var copyIn: ContainerFileSync.CopyIn
        package var getContainer: ContainerFileSync.GetContainer
        package var restartPlans: @Sendable ([ServicePlan]) async throws -> Void

        package init(
            copyIn: @escaping ContainerFileSync.CopyIn = ContainerFileSync.defaultCopyInForInjection,
            getContainer: @escaping ContainerFileSync.GetContainer = ContainerFileSync.defaultGetContainerForInjection,
            restartPlans: @escaping @Sendable ([ServicePlan]) async throws -> Void = { plans in
                try await ServiceRunnerRestart.restartPlans(plans)
            }
        ) {
            self.copyIn = copyIn
            self.getContainer = getContainer
            self.restartPlans = restartPlans
        }
    }

    package static func run(
        configuration: Configuration,
        dependencies: Dependencies = Dependencies()
    ) async throws {
        let eventBuffer = WatchEventBuffer()
        for service in configuration.services {
            for rule in service.rules where rule.rule.initialSync {
                try await ContainerFileSync.initialSync(
                    resolved: rule,
                    containers: service.containers,
                    projectName: configuration.projectName,
                    copyIn: dependencies.copyIn,
                    getContainer: dependencies.getContainer
                )
            }
        }

        let ruleLookup = Dictionary(
            uniqueKeysWithValues: configuration.services.flatMap { service in
                service.rules.map { ($0.ruleID, (service, $0)) }
            }
        )

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await debounceLoop(
                    configuration: configuration,
                    ruleLookup: ruleLookup,
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
        configuration: Configuration,
        ruleLookup: [String: (WatchedService, ResolvedWatchRule)],
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
                guard let (service, rule) = ruleLookup[change.ruleID] else { continue }
                try await applyChange(
                    service: service,
                    rule: rule,
                    hostPath: change.hostPath,
                    projectName: configuration.projectName,
                    dependencies: dependencies
                )
            }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    private static func applyChange(
        service: WatchedService,
        rule: ResolvedWatchRule,
        hostPath: URL,
        projectName: String,
        dependencies: Dependencies
    ) async throws {
        try await ContainerFileSync.sync(
            resolved: rule,
            hostPath: hostPath,
            containers: service.containers,
            projectName: projectName,
            copyIn: dependencies.copyIn,
            getContainer: dependencies.getContainer
        )
        guard rule.rule.action == .syncRestart else { return }

        fputs("Restarting \(service.serviceName) after sync\n", stderr)
        let runningNames = Set(
            service.containers.filter { $0.status == .running }.map(\.name)
        )
        let plansToRestart = service.plans.filter { runningNames.contains($0.name) }
        try await dependencies.restartPlans(plansToRestart)
        // Recreate tears down the container filesystem; copy synced content back in.
        try await ContainerFileSync.sync(
            resolved: rule,
            hostPath: hostPath,
            containers: service.containers,
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
