import Foundation

extension WatchSession {
    package static func makeRuntimes(
        configuration: Configuration,
        dependencies: Dependencies
    ) -> [String: WatchServiceRuntime] {
        var runtimes: [String: WatchServiceRuntime] = [:]
        for service in configuration.services {
            runtimes[service.serviceName] = WatchServiceRuntime(
                serviceName: service.serviceName,
                plans: service.plans,
                containers: service.containers,
                listContainers: dependencies.listProjectContainers,
                getContainer: dependencies.getContainer
            )
        }
        return runtimes
    }

    package static func runInitialSync(
        configuration: Configuration,
        runtimes: [String: WatchServiceRuntime],
        dependencies: Dependencies
    ) async throws {
        for service in configuration.services {
            guard let runtime = runtimes[service.serviceName] else { continue }
            try await runtime.refreshContainers()
            let containers = await runtime.runningContainers()
            for rule in service.rules where rule.rule.initialSync {
                try await ContainerFileSync.initialSync(
                    resolved: rule,
                    containers: containers,
                    projectName: configuration.projectName,
                    copyIn: dependencies.copyIn,
                    getContainer: dependencies.getContainer
                )
            }
        }
    }
}
