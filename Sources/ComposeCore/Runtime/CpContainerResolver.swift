import ContainerResource
import Foundation

package enum CpContainerResolver {
    package static func resolve(
        projectName: String,
        serviceName: String,
        containers: [ProjectContainer],
        index: Int?,
        all: Bool
    ) throws -> [ProjectContainer] {
        if all {
            return try resolveAll(
                projectName: projectName,
                serviceName: serviceName,
                containers: containers
            )
        }
        if let index {
            return try [
                resolveIndexed(
                    projectName: projectName,
                    serviceName: serviceName,
                    containers: containers,
                    index: index
                )
            ]
        }
        return [try ExecContainerResolver.resolve(
            projectName: projectName,
            serviceName: serviceName,
            containers: containers
        )]
    }

    private static func resolveAll(
        projectName: String,
        serviceName: String,
        containers: [ProjectContainer]
    ) throws -> [ProjectContainer] {
        let matches = ProjectStatus.filteredContainers(from: containers, filter: [serviceName])
        guard !matches.isEmpty else {
            throw ComposeError.serviceNotFound(service: serviceName, project: projectName)
        }
        let running = matches.filter { $0.status == .running }
        if running.isEmpty {
            let state = ProjectStatus.formatState(matches[0].status)
            throw ComposeError.serviceNotRunning(service: serviceName, state: state)
        }
        if running.count < matches.count {
            let skipped = matches
                .filter { $0.status != .running }
                .map(\.name)
                .sorted()
                .joined(separator: ", ")
            fputs(
                "Warning: skipping non-running replicas for '\(serviceName)': \(skipped)\n",
                stderr
            )
        }
        return running.sorted { $0.name < $1.name }
    }

    private static func resolveIndexed(
        projectName: String,
        serviceName: String,
        containers: [ProjectContainer],
        index: Int
    ) throws -> ProjectContainer {
        let expectedName = ReplicaPlanning.indexedContainerName(
            projectName: projectName,
            serviceName: serviceName,
            index: index
        )
        let matches = ProjectStatus.filteredContainers(from: containers, filter: [serviceName])
        guard !matches.isEmpty else {
            throw ComposeError.serviceNotFound(service: serviceName, project: projectName)
        }
        guard let match = matches.first(where: { $0.name == expectedName }) else {
            throw ComposeError.replicaNotFound(
                service: serviceName,
                index: index,
                project: projectName
            )
        }
        guard match.status == .running else {
            throw ComposeError.serviceNotRunning(
                service: serviceName,
                state: ProjectStatus.formatState(match.status)
            )
        }
        return match
    }
}
