import Foundation

package struct ProjectPauseRequest: Sendable {
    package let operation: ContainerLifecycle.Operation
    package let scope: ProjectPauseScope
    package let execution: WaveExecutionPolicy
    package let dryRunEnabled: Bool
    package let machineContext: MachineContext
}

package enum ProjectPauseRun {
    package static func run(_ request: ProjectPauseRequest) async throws {
        let scope = request.scope
        let projectContainers = try await ContainerDiscovery.projectContainers(
            forProject: scope.context.projectName,
            machineContext: request.machineContext
        )
        let discovered = projectContainers.map {
            DiscoveredContainer(name: $0.name, serviceName: $0.serviceName)
        }
        let targetNames = try ContainerLifecycle.filteredTargetNames(
            discovered: discovered,
            projectContainers: projectContainers,
            scope: scope,
            operation: request.operation
        )

        guard !targetNames.isEmpty else {
            print(PauseSummary.emptyMessage(operation: request.operation))
            return
        }

        let manifest = request.dryRunEnabled
            ? DryRunManifest(machineName: request.machineContext.machineName)
            : nil
        let affected = try await ContainerLifecycle.apply(
            names: targetNames,
            operation: request.operation,
            execution: request.execution,
            machineContext: request.machineContext,
            dryRunManifest: manifest
        )
        if let manifest {
            await manifest.printLines()
        }
        print(PauseSummary.summaryLine(operation: request.operation, names: affected))
    }
}
