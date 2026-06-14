import ContainerResource
import Foundation
import MachineAPIClient

extension DiskTrim {
    static func trimMachineContainerBeforeDelete(
        containerID: String,
        projectName: String,
        machineContext: MachineContext
    ) async -> String? {
        guard let machineName = machineContext.machineName,
              let snapshot = try? await ComposeContainerGateway.get(id: containerID, machineContext: machineContext),
              snapshot.configuration.labels[ComposeLabels.project] == projectName
        else {
            return "skipped trim for '\(containerID)': not a labeled project container."
        }
        guard let containerPath = await DiskTrimCLI.resolveContainerPath() else {
            return "skipped trim for '\(containerID)': container CLI not found on PATH."
        }

        _ = await DiskTrimCLI.startContainer(
            containerPath: containerPath,
            id: containerID,
            machineName: machineName
        )
        let trim = await DiskTrimCLI.execFstrimRoot(
            containerPath: containerPath,
            id: containerID,
            machineName: machineName
        )
        _ = try? await ComposeContainerGateway.stop(id: containerID, machineContext: machineContext)

        if trim.exitCode == 0 {
            logTrim(projectName: projectName, target: "container", outcome: "trimmed", machine: machineName)
            return nil
        }
        logTrim(projectName: projectName, target: "container", outcome: "skipped", machine: machineName)
        let detail = trim.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return "skipped trim for '\(containerID)': \(detail.isEmpty ? "guest fstrim failed" : detail)."
    }

    static func trimMachineNamedVolume(
        runtimeName: String,
        projectName: String,
        machineContext: MachineContext
    ) async -> String? {
        guard let machineName = machineContext.machineName else { return nil }
        let booted: BootedMachineContext
        do {
            booted = try machineContext.bootedContext()
        } catch {
            return "skipped trim for volume '\(runtimeName)': \(error.localizedDescription)"
        }
        guard let configuration = try? await VolumeRunner.machineVolumeConfiguration(
            snapshot: booted.snapshot,
            name: runtimeName
        ),
            VolumeRunner.isProjectVolume(configuration, projectName: projectName)
        else {
            return nil
        }
        guard DiskTrimHost.isAPFS(path: configuration.source) else {
            return "skipped trim for volume '\(runtimeName)': host volume is not APFS."
        }
        guard let containerPath = await DiskTrimCLI.resolveContainerPath() else {
            return "skipped trim for volume '\(runtimeName)': container CLI not found on PATH."
        }

        let trim = await DiskTrimCLI.trimNamedVolume(
            containerPath: containerPath,
            runtimeName: runtimeName,
            machineName: machineName
        )
        if trim.exitCode == 0 {
            logTrim(projectName: projectName, target: "volume", outcome: "trimmed", machine: machineName)
            return nil
        }
        logTrim(projectName: projectName, target: "volume", outcome: "failed", machine: machineName)
        let detail = trim.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return "skipped trim for volume '\(runtimeName)': \(detail.isEmpty ? "guest fstrim failed" : detail)."
    }
}
