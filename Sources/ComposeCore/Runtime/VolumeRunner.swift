import ContainerAPIClient
import ContainerResource
import Foundation
import MachineAPIClient

/// Creates and removes project-scoped named volumes around container lifecycles.
///
/// Pure naming and validation live in `VolumePlanning`; this module owns the
/// side effects. Mirrors `NetworkRunner`: create runs before startup waves,
/// removal runs after container teardown on `down -v` (best-effort with warnings).
package enum VolumeRunner {
    /// Creates missing project volumes; existing ones are reused as-is.
    package static func createAll(
        _ plans: [VolumePlanning.Plan],
        projectName: String,
        dryRunManifest: DryRunManifest? = nil,
        machineContext: MachineContext = .applicationSandbox
    ) async throws {
        guard !plans.isEmpty else { return }
        if let dryRunManifest {
            for plan in plans {
                await dryRunManifest.recordVolumeCreate(name: plan.runtimeName)
            }
            return
        }
        if machineContext.isMachineMode {
            try await createInMachine(plans, projectName: projectName, machineContext: machineContext)
            return
        }
        let existing = try await listVolumeNames()
        for plan in plans {
            if existing.contains(plan.runtimeName) {
                if let configuration = try? await ClientVolume.inspect(plan.runtimeName),
                   !isProjectVolume(configuration, projectName: projectName) {
                    fputs(
                        "Warning: volume '\(plan.runtimeName)' already exists but wasn't created"
                            + " by this compose project; reusing it.\n",
                        stderr
                    )
                }
                continue
            }
            do {
                _ = try await ClientVolume.create(
                    name: plan.runtimeName,
                    labels: ComposeLabels.volumeLabels(
                        projectName: projectName,
                        logicalName: plan.logicalName
                    )
                )
            } catch {
                throw ComposeError.volumeCreateFailed(volume: plan.logicalName, underlying: error)
            }
        }
    }

    /// Deletes project volumes that still exist; failures warn instead of failing `down`.
    ///
    /// Host removal only targets volumes carrying this project's compose label,
    /// so a same-named volume the user created stays untouched.
    package static func removeProjectVolumes(
        _ plans: [VolumePlanning.Plan],
        projectName: String,
        machineContext: MachineContext = .applicationSandbox
    ) async {
        guard !plans.isEmpty else { return }
        if machineContext.isMachineMode {
            await removeInMachine(plans, projectName: projectName, machineContext: machineContext)
            return
        }
        let removable: Set<String>
        do {
            removable = Set(
                try await ClientVolume.list()
                    .filter { isProjectVolume($0, projectName: projectName) }
                    .map(\.name)
            )
        } catch {
            warnRemoveFailed(names: plans.map(\.runtimeName), error: error)
            return
        }
        let targets = plans.filter { removable.contains($0.runtimeName) }
        await withTaskGroup(of: (name: String, error: Error?).self) { group in
            for plan in targets {
                group.addTask {
                    do {
                        try await ClientVolume.delete(name: plan.runtimeName)
                        return (plan.runtimeName, nil)
                    } catch {
                        return (plan.runtimeName, error)
                    }
                }
            }
            for await result in group {
                if let error = result.error {
                    warnRemoveFailed(names: [result.name], error: error)
                } else {
                    print(result.name)
                }
            }
        }
    }

    private static func createInMachine(
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
            } catch {
                throw ComposeError.volumeCreateFailed(volume: plan.logicalName, underlying: error)
            }
        }
    }

    private static func removeInMachine(
        _ plans: [VolumePlanning.Plan],
        projectName: String,
        machineContext: MachineContext
    ) async {
        let booted: BootedMachineContext
        do {
            booted = try machineContext.bootedContext()
        } catch {
            warnRemoveFailed(names: plans.map(\.runtimeName), error: error)
            return
        }
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
            do {
                try await MachineInVMRunner.run(
                    snapshot: booted.snapshot,
                    containerArguments: machineRemoveArguments(plan: plan)
                )
                print(plan.runtimeName)
            } catch {
                warnRemoveFailed(names: [plan.runtimeName], error: error)
            }
        }
    }

    private static func machineVolumeConfiguration(
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

    private static func machineVolumeNames(snapshot: MachineSnapshot) async throws -> Set<String> {
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

    private static func listVolumeNames() async throws -> Set<String> {
        Set(try await ClientVolume.list().map(\.name))
    }

    private static func warnUnlabeledVolumeReuse(runtimeName: String) {
        fputs(
            "Warning: volume '\(runtimeName)' already exists but wasn't created"
                + " by this compose project; reusing it.\n",
            stderr
        )
    }

    private static func warnRemoveFailed(names: [String], error: Error) {
        let list = names.joined(separator: ", ")
        fputs(
            "Warning: couldn't remove volume(s) \(list): \(error.localizedDescription). "
                + "Remove them with `container volume rm`.\n",
            stderr
        )
    }
}
