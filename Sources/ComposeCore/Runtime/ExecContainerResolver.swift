import ContainerResource
import Foundation

/// Resolves a compose service name to a single running project container (label-scoped).
package enum ExecContainerResolver {
    package static func resolve(
        projectName: String,
        serviceName: String,
        containers: [ProjectContainer]
    ) throws -> ProjectContainer {
        let matches = ProjectStatus.filteredContainers(from: containers, filter: [serviceName])
        guard !matches.isEmpty else {
            throw ComposeError.serviceNotFound(service: serviceName, project: projectName)
        }

        let running = matches.filter { $0.status == .running }
        if running.isEmpty {
            let state = ProjectStatus.formatState(matches[0].status)
            throw ComposeError.serviceNotRunning(service: serviceName, state: state)
        }
        if running.count > 1 {
            throw ComposeError.ambiguousService(
                service: serviceName,
                containers: running.map(\.name)
            )
        }
        return running[0]
    }
}
