import Foundation

package struct ProjectListRequest: Sendable {
    package let inputs: ComposeCommandInputs

    package init(inputs: ComposeCommandInputs) {
        self.inputs = inputs
    }
}

package enum ProjectListRun {
    package static func run(_ request: ProjectListRequest) async throws -> ComposeXPCStatusResponse {
        var warnings: [String] = []
        let resolution = try await MachineContext.resolve(machineName: request.inputs.machineName)
        let machineContext: MachineContext
        if resolution.isMachineMode, !resolution.isMachineRunning {
            warnings.append("Machine stopped; no containers listed.")
            return ComposeXPCStatusResponse(exitStatus: 0, containers: [], warnings: warnings)
        }
        machineContext = resolution

        let context = try await ComposeCommandContext.resolveLabelContext(inputs: request.inputs)
        let containers = try await ContainerDiscovery.projectContainers(
            forProject: context.projectName,
            machineContext: machineContext
        )
        let filter = try ComposeCommandContext.queryServiceFilter(
            context: context,
            inputs: request.inputs
        )
        let rows = ProjectStatus.rows(from: containers, filter: filter)
        let payload = rows.map {
            ComposeXPCContainerRow(
                name: $0.name,
                service: $0.service,
                state: $0.state,
                ports: $0.ports
            )
        }
        return ComposeXPCStatusResponse(exitStatus: 0, containers: payload, warnings: warnings)
    }
}
