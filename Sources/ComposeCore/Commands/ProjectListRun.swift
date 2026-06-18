import Foundation

package struct ProjectListRequest: Sendable {
    package let inputs: ComposeCommandInputs

    package init(inputs: ComposeCommandInputs) {
        self.inputs = inputs
    }
}

package enum ProjectListRun {
    package static func run(_ request: ProjectListRequest) async throws -> ProjectListResult {
        var warnings: [String] = []
        let resolution = try await MachineContext.resolve(machineName: request.inputs.machineName)
        let machineContext: MachineContext
        if resolution.isMachineMode, !resolution.isMachineRunning {
            warnings.append("Machine stopped; no containers listed.")
            return ProjectListResult(rows: [], warnings: warnings)
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
        let rows = ProjectStatus.rows(
            from: containers,
            filter: filter,
            projectName: context.projectName,
            composeFile: context.composeFile
        )
        return ProjectListResult(rows: rows, warnings: warnings)
    }
}
