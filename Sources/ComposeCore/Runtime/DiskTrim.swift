import ContainerAPIClient
import ContainerResource
import Foundation

/// Best-effort APFS sparse reclaim during `compose down --trim` (guest `fstrim` only).
package enum DiskTrim {
    package static func trimContainerBeforeDelete(
        containerID: String,
        projectName: String,
        machineContext: MachineContext
    ) async -> String? {
        guard !machineContext.isMachineMode else {
            return await trimMachineContainerBeforeDelete(
                containerID: containerID,
                projectName: projectName,
                machineContext: machineContext
            )
        }
        return await trimApplicationSandboxContainerBeforeDelete(
            containerID: containerID,
            projectName: projectName,
            machineContext: machineContext
        )
    }

    package static func trimNamedVolumeBeforeDelete(
        runtimeName: String,
        projectName: String,
        machineContext: MachineContext
    ) async -> String? {
        if machineContext.isMachineMode {
            return await trimMachineNamedVolume(
                runtimeName: runtimeName,
                projectName: projectName,
                machineContext: machineContext
            )
        }
        guard let configuration = try? await ClientVolume.inspect(runtimeName),
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
            machineName: nil
        )
        if trim.exitCode == 0 {
            logTrim(projectName: projectName, target: "volume", outcome: "trimmed", machine: "host")
            return nil
        }
        let detail = trim.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        logTrim(projectName: projectName, target: "volume", outcome: "failed", machine: "host")
        return "skipped trim for volume '\(runtimeName)': \(detail.isEmpty ? "guest fstrim failed" : detail)."
    }

    package static func trimMachineGuestAfterProjectTeardown(
        projectName: String,
        machineContext: MachineContext
    ) async -> String? {
        guard machineContext.isMachineMode, let machineName = machineContext.machineName else {
            return nil
        }
        guard let containerPath = await DiskTrimCLI.resolveContainerPath() else {
            return "skipped machine guest trim: container CLI not found on PATH."
        }
        // ponytail: best-effort in-VM helper; may not shrink machine sparse disk until upstream API
        let trim = await DiskTrimCLI.run(
            containerPath: containerPath,
            arguments: [
                "--machine", machineName,
                "run", "--rm", "--cap-add", "SYS_ADMIN",
                DiskTrimHost.trimHelperImage,
                "fstrim", "-a", "-v"
            ]
        )
        if trim.exitCode == 0 {
            logTrim(projectName: projectName, target: "machine", outcome: "trimmed", machine: machineName)
            return nil
        }
        logTrim(projectName: projectName, target: "machine", outcome: "failed", machine: machineName)
        let detail = trim.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return "skipped machine guest trim for '\(machineName)': \(detail.isEmpty ? "guest fstrim failed" : detail)."
    }

    package static func logTrim(
        projectName: String,
        target: String,
        outcome: String,
        machine: String
    ) {
        OsLogTelemetry.enabled {
            OsLogTelemetry.volumes.info(
                """
                event=disk_trim project=\(projectName, privacy: .public) \
                target=\(target, privacy: .public) outcome=\(outcome, privacy: .public) \
                machine=\(machine, privacy: .public)
                """
            )
        }
    }

    package static func emitWarnings(_ warnings: [String]) {
        for warning in warnings {
            fputs("Warning: \(warning)\n", stderr)
        }
    }
}
