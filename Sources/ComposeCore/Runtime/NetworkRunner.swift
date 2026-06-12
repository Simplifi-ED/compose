import ContainerAPIClient
import ContainerResource
import Foundation
import MachineAPIClient

/// Creates and removes project-scoped networks around container lifecycles.
///
/// Pure naming and validation live in `NetworkPlanning`; this module owns the
/// side effects. Mirrors `BuildRunner`: create runs before startup waves,
/// removal runs after container teardown on `down` (best-effort with warnings).
package enum NetworkRunner {
    private static let createPlugin = "container-network-vmnet"

    /// Creates missing project networks; existing ones are reused as-is.
    package static func createAll(
        _ plans: [NetworkPlanning.Plan],
        projectName: String,
        dryRunManifest: DryRunManifest? = nil,
        machineContext: MachineContext = .applicationSandbox
    ) async throws {
        guard !plans.isEmpty else { return }
        if let dryRunManifest {
            for plan in plans {
                await dryRunManifest.recordNetworkCreate(name: plan.runtimeName)
            }
            return
        }
        if machineContext.isMachineMode {
            try await createInMachine(plans, projectName: projectName, machineContext: machineContext)
            return
        }
        guard #available(macOS 26, *) else {
            throw ComposeError.networksRequireMacOS26
        }
        let client = NetworkClient()
        let resourcesByID = Dictionary(
            try await client.list().map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for plan in plans {
            if let resource = resourcesByID[plan.runtimeName] {
                if !isProjectNetwork(resource, projectName: projectName) {
                    fputs(
                        "Warning: network '\(plan.runtimeName)' already exists but wasn't created"
                            + " by this compose project; reusing it.\n",
                        stderr
                    )
                }
                continue
            }
            do {
                let configuration = try NetworkConfiguration(
                    name: plan.runtimeName,
                    mode: .nat,
                    labels: ResourceLabels(ComposeLabels.networkLabels(
                        projectName: projectName,
                        logicalName: plan.logicalName
                    )),
                    plugin: createPlugin
                )
                _ = try await client.create(configuration: configuration)
            } catch {
                throw ComposeError.networkCreateFailed(network: plan.logicalName, underlying: error)
            }
        }
    }

    /// Deletes project networks that still exist; failures (for example
    /// containers still attached) warn instead of failing `down`.
    ///
    /// Host removal only targets networks carrying this project's compose label,
    /// so a same-named network the user created stays untouched.
    package static func removeProjectNetworks(
        _ plans: [NetworkPlanning.Plan],
        projectName: String,
        machineContext: MachineContext = .applicationSandbox
    ) async {
        guard !plans.isEmpty else { return }
        if machineContext.isMachineMode {
            await removeInMachine(plans, machineContext: machineContext)
            return
        }
        let client = NetworkClient()
        let removable: Set<String>
        do {
            removable = Set(
                try await client.list()
                    .filter { !$0.isBuiltin && isProjectNetwork($0, projectName: projectName) }
                    .map(\.id)
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
                        try await client.delete(id: plan.runtimeName)
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
        _ plans: [NetworkPlanning.Plan],
        projectName: String,
        machineContext: MachineContext
    ) async throws {
        let booted = try machineContext.bootedContext()
        let existing = try await machineNetworkNames(snapshot: booted.snapshot)
        for plan in plans where !existing.contains(plan.runtimeName) {
            do {
                var arguments = ["network", "create"]
                for (key, value) in ComposeLabels.networkLabels(
                    projectName: projectName,
                    logicalName: plan.logicalName
                ).sorted(by: { $0.key < $1.key }) {
                    arguments.append(contentsOf: ["--label", "\(key)=\(value)"])
                }
                arguments.append(plan.runtimeName)
                try await MachineInVMRunner.run(snapshot: booted.snapshot, containerArguments: arguments)
            } catch {
                throw ComposeError.networkCreateFailed(network: plan.logicalName, underlying: error)
            }
        }
    }

    private static func removeInMachine(
        _ plans: [NetworkPlanning.Plan],
        machineContext: MachineContext
    ) async {
        let booted: BootedMachineContext
        let existing: Set<String>
        do {
            booted = try machineContext.bootedContext()
            existing = try await machineNetworkNames(snapshot: booted.snapshot)
        } catch {
            warnRemoveFailed(names: plans.map(\.runtimeName), error: error)
            return
        }
        for plan in plans where existing.contains(plan.runtimeName) {
            do {
                try await MachineInVMRunner.run(
                    snapshot: booted.snapshot,
                    containerArguments: ["network", "delete", plan.runtimeName]
                )
                print(plan.runtimeName)
            } catch {
                warnRemoveFailed(names: [plan.runtimeName], error: error)
            }
        }
    }

    private static func machineNetworkNames(snapshot: MachineSnapshot) async throws -> Set<String> {
        let capture = try await MachineInVMRunner.runCapturing(
            snapshot: snapshot,
            containerArguments: ["network", "list", "--quiet"]
        )
        guard capture.exitCode == 0 else {
            throw ComposeError.machineCommandFailed(
                machine: snapshot.id,
                command: "network list",
                exitCode: capture.exitCode
            )
        }
        return Set(capture.stdout.split(separator: "\n").map(String.init))
    }

    private static func isProjectNetwork(_ resource: NetworkResource, projectName: String) -> Bool {
        resource.labels.contains { $0 == ComposeLabels.project && $1 == projectName }
    }

    private static func warnRemoveFailed(names: [String], error: Error) {
        let list = names.joined(separator: ", ")
        fputs(
            "Warning: couldn't remove network(s) \(list): \(error.localizedDescription). "
                + "Remove them with `container network rm`.\n",
            stderr
        )
    }
}
