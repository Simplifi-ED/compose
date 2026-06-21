import ContainerResource
import Foundation
import MachineAPIClient

extension NetworkRunner {
    static func createInMachine(
        _ plans: [NetworkPlanning.Plan],
        projectName: String,
        machineContext: MachineContext
    ) async throws {
        let booted = try machineContext.bootedContext()
        for plan in plans {
            if plan.mode == .bridge {
                throw ComposeError.bridgeNetworksUnsupported(network: plan.logicalName)
            }
            if let resource = try await machineNetworkResource(
                snapshot: booted.snapshot,
                name: plan.runtimeName
            ) {
                if !isProjectNetwork(resource, projectName: projectName) {
                    warnUnlabeledNetworkReuse(runtimeName: plan.runtimeName)
                }
                continue
            }
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
                logNetworkCreate(
                    projectName: projectName,
                    plan: plan,
                    machine: machineContext.machineName ?? "host"
                )
            } catch {
                logNetworkCreateFailed(projectName: projectName, plan: plan, error: error)
                throw ComposeError.networkCreateFailed(network: plan.logicalName, underlying: error)
            }
        }
    }

    static func removeInMachine(
        _ plans: [NetworkPlanning.Plan],
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
            let resource: NetworkResource
            do {
                guard let inspected = try await machineNetworkResource(
                    snapshot: booted.snapshot,
                    name: plan.runtimeName
                ) else {
                    continue
                }
                resource = inspected
            } catch {
                warnRemoveFailed(names: [plan.runtimeName], error: error)
                continue
            }
            guard !resource.isBuiltin,
                  isProjectNetwork(resource, projectName: projectName) else {
                continue
            }
            do {
                try await MachineInVMRunner.run(
                    snapshot: booted.snapshot,
                    containerArguments: ["network", "delete", plan.runtimeName]
                )
                print(plan.runtimeName)
                logNetworkRemove(
                    projectName: projectName,
                    runtimeName: plan.runtimeName,
                    machine: machineContext.machineName ?? "host"
                )
            } catch {
                warnRemoveFailed(names: [plan.runtimeName], error: error)
            }
        }
    }

    static func machineNetworkResource(
        snapshot: MachineSnapshot,
        name: String
    ) async throws -> NetworkResource? {
        let capture = try await MachineInVMRunner.runCapturing(
            snapshot: snapshot,
            containerArguments: ["network", "inspect", name]
        )
        guard capture.exitCode == 0 else { return nil }
        let trimmed = capture.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return try JSONDecoder().decode([NetworkResource].self, from: Data(trimmed.utf8)).first
    }
}
