import ContainerAPIClient
import ContainerCommands
import ContainerResource
import Foundation

/// Routes container I/O to the application sandbox or an in-machine `container` CLI.
///
/// **Machine mode contracts**
/// - ``list(filters:machineContext:)`` accepts an inspected context (running or stopped).
///   Returns an empty list when the machine is stopped.
/// - All other machine-mode methods require a **booted, running** machine. Call
///   ``MachineContext/ensureBooted()`` on mutating commands, then pass the returned context
///   (or call ``MachineContext/bootedContext()`` before in-VM I/O).
package enum ComposeContainerGateway {
    package static let pauseSignal = "SIGSTOP"
    package static let unpauseSignal = "SIGCONT"

    package static func list(
        filters: ContainerListFilters,
        machineContext: MachineContext = .applicationSandbox,
        hostClient: ContainerClient? = nil
    ) async throws -> [ContainerSnapshot] {
        if machineContext.isMachineMode {
            guard machineContext.isMachineRunning else { return [] }
            let booted = try machineContext.bootedContext()
            let managed = try await MachineInVMRunner.listContainers(snapshot: booted.snapshot)
            return managed.map { item in
                ContainerSnapshot(
                    configuration: item.configuration,
                    status: item.status.state,
                    networks: item.status.networks,
                    startedDate: item.status.startedDate
                )
            }.filter { snapshotMatchesFilters($0, filters: filters) }
        }
        if let hostClient {
            return try await hostClient.list(filters: filters)
        }
        return try await ContainerClient().list(filters: filters)
    }

    package static func get(
        id: String,
        machineContext: MachineContext = .applicationSandbox
    ) async throws -> ContainerSnapshot {
        if machineContext.isMachineMode {
            let containers = try await list(filters: .init(ids: [id]), machineContext: machineContext)
            guard let container = containers.first else {
                throw ComposeError.containerNotFound(container: id)
            }
            return container
        }
        return try await ContainerClient().get(id: id)
    }

    package static func runDetached(
        plan: ServicePlan,
        machineContext: MachineContext = .applicationSandbox
    ) async throws {
        let machine = machineContext.machineName ?? "host"
        if machineContext.isMachineMode {
            let booted = try machineContext.bootedContext()
            let existing = try await list(
                filters: .init(ids: [plan.name]),
                machineContext: machineContext
            )
            if !existing.isEmpty {
                logLifecycleReplace(plan: plan, machine: machine)
                try await ContainerTeardown.teardown(id: plan.name, machineContext: machineContext)
            }
            let runArguments = try ComposeFileStaging.preparedRunArguments(for: plan)
            try await MachineInVMRunner.run(
                snapshot: booted.snapshot,
                containerArguments: ["run"] + runArguments
            )
            logLifecycleStart(plan: plan, machine: machine)
            return
        }
        try await ServiceRunner.runContainerWithFileMounts(plan, machineContext: machineContext)
    }

    package static func pause(
        id: String,
        machineContext: MachineContext = .applicationSandbox
    ) async throws {
        try await kill(id: id, signal: Self.pauseSignal, machineContext: machineContext)
    }

    package static func unpause(
        id: String,
        machineContext: MachineContext = .applicationSandbox
    ) async throws {
        try await kill(id: id, signal: Self.unpauseSignal, machineContext: machineContext)
    }

    package static func stop(
        id: String,
        opts: ContainerStopOptions? = nil,
        machineContext: MachineContext = .applicationSandbox
    ) async throws {
        let machine = machineContext.machineName ?? "host"
        if machineContext.isMachineMode {
            let booted = try machineContext.bootedContext()
            var args = ["stop", id]
            if let timeout = opts?.timeoutInSeconds {
                args.append(contentsOf: ["--timeout", String(timeout)])
            }
            try await MachineInVMRunner.run(snapshot: booted.snapshot, containerArguments: args)
            logLifecycleStop(id: id, machine: machine)
            return
        }
        let client = ContainerClient()
        if let opts {
            try await client.stop(id: id, opts: opts)
        } else {
            try await client.stop(id: id)
        }
        logLifecycleStop(id: id, machine: machine)
    }

    package static func kill(
        id: String,
        signal: String,
        machineContext: MachineContext = .applicationSandbox
    ) async throws {
        if machineContext.isMachineMode {
            let booted = try machineContext.bootedContext()
            try await MachineInVMRunner.run(
                snapshot: booted.snapshot,
                containerArguments: ["kill", "--signal", signal, id]
            )
            return
        }
        try await ContainerClient().kill(id: id, signal: signal)
    }

    package static func delete(
        id: String,
        force: Bool = true,
        machineContext: MachineContext = .applicationSandbox
    ) async throws {
        let machine = machineContext.machineName ?? "host"
        if machineContext.isMachineMode {
            let booted = try machineContext.bootedContext()
            var args = ["delete", id]
            if force {
                args.insert("--force", at: 1)
            }
            try await MachineInVMRunner.run(snapshot: booted.snapshot, containerArguments: args)
            logLifecycleRemove(id: id, machine: machine)
            return
        }
        try await ContainerClient().delete(id: id, force: force)
        logLifecycleRemove(id: id, machine: machine)
    }

    private static func logLifecycleReplace(plan: ServicePlan, machine: String) {
        OsLogTelemetry.enabled {
            OsLogTelemetry.lifecycle.info(
                """
                event=container_replace project=\(plan.projectName, privacy: .public) \
                service=\(plan.serviceName, privacy: .public) \
                container=\(plan.name, privacy: .public) machine=\(machine, privacy: .public)
                """
            )
        }
    }

    private static func logLifecycleStart(plan: ServicePlan, machine: String) {
        OsLogTelemetry.enabled {
            OsLogTelemetry.lifecycle.info(
                """
                event=container_start project=\(plan.projectName, privacy: .public) \
                service=\(plan.serviceName, privacy: .public) container=\(plan.name, privacy: .public) \
                replica=\(plan.replicaIndex, privacy: .public) machine=\(machine, privacy: .public)
                """
            )
        }
    }

    private static func logLifecycleStop(id: String, machine: String) {
        OsLogTelemetry.enabled {
            OsLogTelemetry.lifecycle.info(
                "event=container_stop container=\(id, privacy: .public) machine=\(machine, privacy: .public)"
            )
        }
    }

    private static func logLifecycleRemove(id: String, machine: String) {
        OsLogTelemetry.enabled {
            OsLogTelemetry.lifecycle.info(
                "event=container_remove container=\(id, privacy: .public) machine=\(machine, privacy: .public)"
            )
        }
    }

    private static func snapshotMatchesFilters(
        _ snapshot: ContainerSnapshot,
        filters: ContainerListFilters
    ) -> Bool {
        if !filters.ids.isEmpty, !filters.ids.contains(snapshot.id) {
            return false
        }
        if let status = filters.status, snapshot.status != status {
            return false
        }
        for (key, pattern) in filters.labels {
            let value = snapshot.configuration.labels[key] ?? ""
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            if regex.firstMatch(in: value, range: range) == nil {
                return false
            }
        }
        return true
    }
}
