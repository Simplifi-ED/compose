import ContainerResource
import Foundation

extension VolumeRunner {
    /// In-VM `container volume create` arguments for one project volume.
    package static func machineCreateArguments(
        plan: VolumePlanning.Plan,
        projectName: String
    ) -> [String] {
        var arguments = ["volume", "create"]
        for (key, value) in ComposeLabels.volumeLabels(
            projectName: projectName,
            logicalName: plan.logicalName
        ).sorted(by: { $0.key < $1.key }) {
            arguments.append(contentsOf: ["--label", "\(key)=\(value)"])
        }
        arguments.append(plan.runtimeName)
        return arguments
    }

    package static func machineRemoveArguments(plan: VolumePlanning.Plan) -> [String] {
        ["volume", "rm", plan.runtimeName]
    }

    package static func machineInspectArguments(name: String) -> [String] {
        ["volume", "inspect", name]
    }

    package static func machineListArguments() -> [String] {
        ["volume", "list", "--quiet"]
    }

    /// True when the volume carries this compose project's label.
    package static func isProjectVolume(_ configuration: VolumeConfiguration, projectName: String) -> Bool {
        configuration.labels[ComposeLabels.project] == projectName
    }

    /// Machine `down -v` only removes volumes that pass inspect + project-label gating.
    package static func shouldRemoveInMachine(
        configuration: VolumeConfiguration?,
        projectName: String
    ) -> Bool {
        guard let configuration else { return false }
        return isProjectVolume(configuration, projectName: projectName)
    }
}
