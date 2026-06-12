import ContainerResource
import Foundation

extension ContainerDiscovery {
    package static func listFilters(
        forProject projectName: String,
        machineContext: MachineContext = .applicationSandbox
    ) -> ContainerListFilters {
        var labels = [ComposeLabels.project: exactMatchRegex(projectName)]
        if let machineName = machineContext.machineName {
            labels[ComposeLabels.machine] = ContainerDiscovery.exactMatchRegex(machineName)
        }
        return ContainerListFilters(labels: labels).withoutMachines()
    }
}
