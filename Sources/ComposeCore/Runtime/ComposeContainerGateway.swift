import ContainerAPIClient
import ContainerCommands
import ContainerResource
import Foundation

/// Routes container I/O to the application sandbox or an in-machine `container` CLI.
package enum ComposeContainerGateway {
    package static func list(
        filters: ContainerListFilters,
        machineContext: MachineContext = .applicationSandbox
    ) async throws -> [ContainerSnapshot] {
        if machineContext.isMachineMode {
            let snapshot = try machineContext.requireSnapshot()
            let managed = try await MachineInVMRunner.listContainers(snapshot: snapshot)
            return managed.map { item in
                ContainerSnapshot(
                    configuration: item.configuration,
                    status: item.status.state,
                    networks: item.status.networks,
                    startedDate: item.status.startedDate
                )
            }.filter { snapshotMatchesFilters($0, filters: filters) }
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
                throw ComposeError.serviceNotFound(service: id, project: "")
            }
            return container
        }
        return try await ContainerClient().get(id: id)
    }

    package static func runDetached(
        plan: ServicePlan,
        machineContext: MachineContext = .applicationSandbox
    ) async throws {
        if machineContext.isMachineMode {
            let snapshot = try machineContext.requireSnapshot()
            try? await ContainerTeardown.teardown(id: plan.name, machineContext: machineContext)
            let runArguments = try ComposeFileStaging.preparedRunArguments(for: plan)
            try await MachineInVMRunner.run(
                snapshot: snapshot,
                containerArguments: ["run"] + runArguments
            )
            return
        }
        try await ServiceRunner.runContainerWithFileMounts(plan, machineContext: machineContext)
    }

    package static func stop(
        id: String,
        opts: ContainerStopOptions? = nil,
        machineContext: MachineContext = .applicationSandbox
    ) async throws {
        if machineContext.isMachineMode {
            let snapshot = try machineContext.requireSnapshot()
            var args = ["stop", id]
            if let timeout = opts?.timeoutInSeconds {
                args.append(contentsOf: ["--timeout", String(timeout)])
            }
            try await MachineInVMRunner.run(snapshot: snapshot, containerArguments: args)
            return
        }
        let client = ContainerClient()
        if let opts {
            try await client.stop(id: id, opts: opts)
        } else {
            try await client.stop(id: id)
        }
    }

    package static func kill(
        id: String,
        signal: String,
        machineContext: MachineContext = .applicationSandbox
    ) async throws {
        if machineContext.isMachineMode {
            let snapshot = try machineContext.requireSnapshot()
            try await MachineInVMRunner.run(
                snapshot: snapshot,
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
        if machineContext.isMachineMode {
            let snapshot = try machineContext.requireSnapshot()
            var args = ["delete", id]
            if force {
                args.insert("--force", at: 1)
            }
            try await MachineInVMRunner.run(snapshot: snapshot, containerArguments: args)
            return
        }
        try await ContainerClient().delete(id: id, force: force)
    }

    package static func copyIn(
        id: String,
        source: String,
        destination: String,
        mode: UInt32,
        createParents: Bool,
        machineContext: MachineContext = .applicationSandbox
    ) async throws {
        if machineContext.isMachineMode {
            throw ComposeError.machineUnsupportedOperation("copy in")
        }
        try await ContainerClient().copyIn(
            id: id,
            source: source,
            destination: destination,
            mode: mode,
            createParents: createParents
        )
    }

    package static func copyOut(
        id: String,
        source: String,
        destination: String,
        createParents: Bool,
        machineContext: MachineContext = .applicationSandbox
    ) async throws {
        if machineContext.isMachineMode {
            throw ComposeError.machineUnsupportedOperation("copy out")
        }
        try await ContainerClient().copyOut(
            id: id,
            source: source,
            destination: destination,
            createParents: createParents
        )
    }

    package static func createProcess(
        containerId: String,
        processId: String,
        configuration: ProcessConfiguration,
        stdio: [FileHandle?],
        machineContext: MachineContext = .applicationSandbox
    ) async throws -> any ClientProcess {
        if machineContext.isMachineMode {
            throw ComposeError.machineUnsupportedOperation("exec")
        }
        return try await ContainerClient().createProcess(
            containerId: containerId,
            processId: processId,
            configuration: configuration,
            stdio: stdio
        )
    }

    package static func logs(
        id: String,
        machineContext: MachineContext = .applicationSandbox
    ) async throws -> [FileHandle] {
        if machineContext.isMachineMode {
            throw ComposeError.machineUnsupportedOperation("logs streaming")
        }
        return try await ContainerClient().logs(id: id)
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
