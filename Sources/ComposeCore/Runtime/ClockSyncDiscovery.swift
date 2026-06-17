import ContainerResource
import Foundation
import MachineAPIClient

package enum ClockSyncDiscovery {
    package struct Targets: Sendable, Equatable {
        package let hostContainerIDs: [String]
        package let machineHypervisorIDs: [String]

        package var isEmpty: Bool {
            hostContainerIDs.isEmpty && machineHypervisorIDs.isEmpty
        }

        package var totalCount: Int {
            hostContainerIDs.count + machineHypervisorIDs.count
        }
    }

    package static let projectLabelPattern = "^.+$"

    package static func hostContainerIDs(from snapshots: [ContainerSnapshot]) -> [String] {
        snapshots
            .filter { snapshot in
                snapshot.status == .running
                    && snapshot.configuration.labels[ComposeLabels.project] != nil
                    && snapshot.configuration.labels[ComposeLabels.machine] == nil
            }
            .map(\.id)
            .sorted()
    }

    package static func machineHypervisorIDs(
        machines: [MachineSnapshot],
        inVMContainers: [String: [ManagedContainer]]
    ) -> [String] {
        machines.compactMap { machine in
            guard MachineContext.isRunning(machine),
                  let hypervisorID = machine.containerId else { return nil }
            let containers = inVMContainers[machine.id] ?? []
            let hasComposeWorkload = containers.contains { container in
                container.configuration.labels[ComposeLabels.project] != nil
                    && container.status.state == .running
            }
            return hasComposeWorkload ? hypervisorID : nil
        }
        .sorted()
    }
}
