import ContainerResource
import Foundation

/// Label and runtime checks shared by exec-adjacent copy/sync paths.
package enum ComposeContainerGuard {
    package static func verifyRunningProjectService(
        snapshot: ContainerSnapshot,
        containerName: String,
        projectName: String,
        serviceName: String,
        fieldName: String = "cp"
    ) throws {
        let labelProject = snapshot.configuration.labels[ComposeLabels.project]
        guard labelProject == projectName else {
            throw ComposeError.containerProjectMismatch(
                container: containerName,
                project: projectName
            )
        }
        let labelService = snapshot.configuration.labels[ComposeLabels.service]
        guard labelService == serviceName else {
            throw ComposeError.invalidField(
                fieldName,
                reason: "container '\(containerName)' belongs to service '\(labelService ?? "unknown")', "
                    + "not '\(serviceName)'"
            )
        }
        guard snapshot.status == .running else {
            throw ComposeError.serviceNotRunning(
                service: serviceName,
                state: ProjectStatus.formatState(snapshot.status)
            )
        }
    }
}
