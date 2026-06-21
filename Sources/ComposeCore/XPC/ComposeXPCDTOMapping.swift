import Foundation

package enum ComposeXPCDTOMapping {
    package static func statusResponse(from result: ProjectListResult) -> ComposeXPCStatusResponse {
        ComposeXPCStatusResponse(
            exitStatus: 0,
            containers: result.rows.map(containerRow(from:)),
            warnings: result.warnings
        )
    }

    package static func mutationResponse(from result: ProjectMutationResult) -> ComposeXPCMutationResponse {
        ComposeXPCMutationResponse(
            exitStatus: 0,
            affectedContainers: result.affectedContainers,
            warnings: result.warnings
        )
    }

    private static func containerRow(from row: ProjectStatusRow) -> ComposeXPCContainerRow {
        ComposeXPCContainerRow(
            name: row.name,
            service: row.service,
            state: row.state,
            ports: row.ports,
            ipAddress: row.ipAddress.isEmpty ? nil : row.ipAddress
        )
    }
}
