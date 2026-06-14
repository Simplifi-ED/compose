import ContainerResource
import Foundation
import MachineAPIClient

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

    static func createInMachine(
        _ plans: [VolumePlanning.Plan],
        projectName: String,
        machineContext: MachineContext
    ) async throws {
        let booted = try machineContext.bootedContext()
        let existing = try await machineVolumeNames(snapshot: booted.snapshot)
        for plan in plans {
            if existing.contains(plan.runtimeName) {
                if let configuration = try? await machineVolumeConfiguration(
                    snapshot: booted.snapshot,
                    name: plan.runtimeName
                ),
                    !isProjectVolume(configuration, projectName: projectName) {
                    warnUnlabeledVolumeReuse(runtimeName: plan.runtimeName)
                }
                continue
            }
            do {
                let arguments = machineCreateArguments(plan: plan, projectName: projectName)
                try await MachineInVMRunner.run(snapshot: booted.snapshot, containerArguments: arguments)
                logVolumeCreate(
                    projectName: projectName,
                    plan: plan,
                    machine: machineContext.machineName ?? "host"
                )
            } catch {
                logVolumeCreateFailed(projectName: projectName, plan: plan, error: error)
                throw ComposeError.volumeCreateFailed(volume: plan.logicalName, underlying: error)
            }
        }
    }

    static func removeInMachine(
        _ plans: [VolumePlanning.Plan],
        projectName: String,
        machineContext: MachineContext,
        trimBeforeDelete: Bool = false
    ) async {
        let booted: BootedMachineContext
        do {
            booted = try machineContext.bootedContext()
        } catch {
            warnRemoveFailed(names: plans.map(\.runtimeName), error: error)
            return
        }
        var trimWarnings: [String] = []
        for plan in plans {
            let configuration: VolumeConfiguration?
            do {
                configuration = try await machineVolumeConfiguration(
                    snapshot: booted.snapshot,
                    name: plan.runtimeName
                )
            } catch {
                warnRemoveFailed(names: [plan.runtimeName], error: error)
                continue
            }
            guard let configuration, isProjectVolume(configuration, projectName: projectName) else {
                continue
            }
            if trimBeforeDelete,
               let warning = await DiskTrim.trimNamedVolumeBeforeDelete(
                   runtimeName: plan.runtimeName,
                   projectName: projectName,
                   machineContext: machineContext
               ) {
                trimWarnings.append(warning)
            }
            do {
                try await MachineInVMRunner.run(
                    snapshot: booted.snapshot,
                    containerArguments: machineRemoveArguments(plan: plan)
                )
                print(plan.runtimeName)
                logVolumeRemove(
                    projectName: projectName,
                    runtimeName: plan.runtimeName,
                    machine: machineContext.machineName ?? "host"
                )
            } catch {
                warnRemoveFailed(names: [plan.runtimeName], error: error)
            }
        }
        DiskTrim.emitWarnings(trimWarnings)
    }

    static func machineVolumeConfiguration(
        snapshot: MachineSnapshot,
        name: String
    ) async throws -> VolumeConfiguration? {
        let capture = try await MachineInVMRunner.runCapturing(
            snapshot: snapshot,
            containerArguments: machineInspectArguments(name: name)
        )
        guard capture.exitCode == 0 else { return nil }
        let trimmed = capture.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return try JSONDecoder().decode([VolumeConfiguration].self, from: Data(trimmed.utf8)).first
    }

    static func machineVolumeNames(snapshot: MachineSnapshot) async throws -> Set<String> {
        let capture = try await MachineInVMRunner.runCapturing(
            snapshot: snapshot,
            containerArguments: machineListArguments()
        )
        guard capture.exitCode == 0 else {
            throw ComposeError.machineCommandFailed(
                machine: snapshot.id,
                command: "volume list",
                exitCode: capture.exitCode
            )
        }
        return Set(capture.stdout.split(separator: "\n").map(String.init))
    }
}
