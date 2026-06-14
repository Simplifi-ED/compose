import ContainerAPIClient
import ContainerResource
import Foundation

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
        try await SignpostTelemetry.interval(SignpostTelemetry.network, category: .networks) {
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
                        warnUnlabeledNetworkReuse(runtimeName: plan.runtimeName)
                    }
                    continue
                }
                try await createHostNetwork(plan: plan, projectName: projectName, client: client)
            }
        }
    }

    private static func createHostNetwork(
        plan: NetworkPlanning.Plan,
        projectName: String,
        client: NetworkClient
    ) async throws {
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
            logNetworkCreate(projectName: projectName, plan: plan, machine: "host")
        } catch {
            logNetworkCreateFailed(projectName: projectName, plan: plan, error: error)
            throw ComposeError.networkCreateFailed(network: plan.logicalName, underlying: error)
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
            await removeInMachine(plans, projectName: projectName, machineContext: machineContext)
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
                    logNetworkRemove(projectName: projectName, runtimeName: result.name, machine: "host")
                }
            }
        }
    }

    package static func isProjectNetwork(_ resource: NetworkResource, projectName: String) -> Bool {
        resource.labels.contains { $0 == ComposeLabels.project && $1 == projectName }
    }

    package static func warnUnlabeledNetworkReuse(runtimeName: String) {
        fputs(
            "Warning: network '\(runtimeName)' already exists but wasn't created"
                + " by this compose project; reusing it.\n",
            stderr
        )
    }

    package static func warnRemoveFailed(names: [String], error: Error) {
        let list = names.joined(separator: ", ")
        fputs(
            "Warning: couldn't remove network(s) \(list): \(error.localizedDescription). "
                + "Remove them with `container network rm`.\n",
            stderr
        )
    }

    package static func logNetworkCreate(
        projectName: String,
        plan: NetworkPlanning.Plan,
        machine: String
    ) {
        OsLogTelemetry.enabled {
            OsLogTelemetry.networks.info(
                """
                event=network_create project=\(projectName, privacy: .public) \
                network=\(plan.logicalName, privacy: .public) \
                runtime=\(plan.runtimeName, privacy: .public) \
                machine=\(machine, privacy: .public)
                """
            )
        }
    }

    package static func logNetworkCreateFailed(
        projectName: String,
        plan: NetworkPlanning.Plan,
        error: Error
    ) {
        OsLogTelemetry.enabled {
            OsLogTelemetry.networks.error(
                """
                event=network_create_failed project=\(projectName, privacy: .public) \
                network=\(plan.logicalName, privacy: .public) \
                error_type=\(String(describing: type(of: error)), privacy: .public)
                """
            )
        }
    }

    package static func logNetworkRemove(projectName: String, runtimeName: String, machine: String) {
        OsLogTelemetry.enabled {
            OsLogTelemetry.networks.info(
                """
                event=network_remove project=\(projectName, privacy: .public) \
                runtime=\(runtimeName, privacy: .public) machine=\(machine, privacy: .public)
                """
            )
        }
    }
}
