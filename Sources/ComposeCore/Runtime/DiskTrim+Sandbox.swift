import ContainerAPIClient
import Foundation

extension DiskTrim {
    static func trimApplicationSandboxContainerBeforeDelete(
        containerID: String,
        projectName: String,
        machineContext: MachineContext
    ) async -> String? {
        guard let snapshot = try? await ComposeContainerGateway.get(id: containerID, machineContext: machineContext)
        else {
            return "skipped trim for '\(containerID)': container unavailable for trim."
        }
        guard snapshot.configuration.labels[ComposeLabels.project] == projectName else {
            return "skipped trim for '\(containerID)': not a labeled project container."
        }

        let rootfs = DiskTrimHost.containerRootfsPath(
            containerID: containerID,
            appRoot: DiskTrimHost.defaultAppRoot()
        )
        guard FileManager.default.fileExists(atPath: rootfs) else {
            return "skipped trim for '\(containerID)': root filesystem path unavailable."
        }
        guard DiskTrimHost.isAPFS(path: rootfs) else {
            return "skipped trim for '\(containerID)': host volume is not APFS."
        }

        guard let containerPath = await DiskTrimCLI.resolveContainerPath() else {
            return "skipped trim for '\(containerID)': container CLI not found on PATH."
        }

        _ = await DiskTrimCLI.startContainer(
            containerPath: containerPath,
            id: containerID,
            machineName: nil
        )
        let trim = await DiskTrimCLI.execFstrimRoot(
            containerPath: containerPath,
            id: containerID,
            machineName: nil
        )
        _ = try? await ComposeContainerGateway.stop(id: containerID, machineContext: machineContext)

        return containerTrimOutcome(
            containerID: containerID,
            projectName: projectName,
            trim: trim,
            machine: "host"
        )
    }

    static func containerTrimOutcome(
        containerID: String,
        projectName: String,
        trim: DiskTrimCLI.Result,
        machine: String
    ) -> String? {
        if trim.exitCode == 0 {
            logTrim(projectName: projectName, target: "container", outcome: "trimmed", machine: machine)
            return nil
        }
        let detail = trim.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        logTrim(projectName: projectName, target: "container", outcome: "skipped", machine: machine)
        if detail.localizedCaseInsensitiveContains("not permitted") {
            return """
            skipped trim for '\(containerID)': guest fstrim requires CAP_SYS_ADMIN in the container. \
            Named volumes still trim via a privileged helper when using `down -v --trim`.
            """
        }
        return "skipped trim for '\(containerID)': \(detail.isEmpty ? "guest fstrim failed" : detail)."
    }
}
