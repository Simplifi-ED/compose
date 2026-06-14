import ContainerAPIClient
import ContainerResource
import Foundation

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
                    warnUnlabeledVolumeReuse(runtimeName: plan.runtimeName)
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
                logVolumeCreate(projectName: projectName, plan: plan, machine: "host")
            } catch {
                logVolumeCreateFailed(projectName: projectName, plan: plan, error: error)
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
                    logVolumeRemove(projectName: projectName, runtimeName: result.name, machine: "host")
                }
            }
        }
    }

    private static func listVolumeNames() async throws -> Set<String> {
        Set(try await ClientVolume.list().map(\.name))
    }

    package static func warnUnlabeledVolumeReuse(runtimeName: String) {
        fputs(
            "Warning: volume '\(runtimeName)' already exists but wasn't created"
                + " by this compose project; reusing it.\n",
            stderr
        )
    }

    package static func logVolumeCreate(
        projectName: String,
        plan: VolumePlanning.Plan,
        machine: String
    ) {
        OsLogTelemetry.enabled {
            OsLogTelemetry.volumes.info(
                """
                event=volume_create project=\(projectName, privacy: .public) \
                volume=\(plan.logicalName, privacy: .public) runtime=\(plan.runtimeName, privacy: .public) \
                machine=\(machine, privacy: .public)
                """
            )
        }
    }

    package static func logVolumeCreateFailed(
        projectName: String,
        plan: VolumePlanning.Plan,
        error: Error
    ) {
        OsLogTelemetry.enabled {
            OsLogTelemetry.volumes.error(
                """
                event=volume_create_failed project=\(projectName, privacy: .public) \
                volume=\(plan.logicalName, privacy: .public) \
                error_type=\(String(describing: type(of: error)), privacy: .public)
                """
            )
        }
    }

    package static func logVolumeRemove(projectName: String, runtimeName: String, machine: String) {
        OsLogTelemetry.enabled {
            OsLogTelemetry.volumes.info(
                """
                event=volume_remove project=\(projectName, privacy: .public) \
                runtime=\(runtimeName, privacy: .public) machine=\(machine, privacy: .public)
                """
            )
        }
    }

    package static func warnRemoveFailed(names: [String], error: Error) {
        let list = names.joined(separator: ", ")
        fputs(
            "Warning: couldn't remove volume(s) \(list): \(error.localizedDescription). "
                + "Remove them with `container volume rm`.\n",
            stderr
        )
    }
}
