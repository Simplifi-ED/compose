import ContainerAPIClient
import Containerization
import ContainerResource
import Darwin
import Foundation
import MachineAPIClient
import NIOCore
import NIOPosix

package enum ClockSync {
    /// Manual acceptance threshold; see `docs/clock-sync-manual-test.md`.
    package static let skewThresholdSeconds = 5

    package static let failureWarning =
        """
        Warning: Couldn't sync container clocks after wake. Run a compose command again \
        or set COMPOSE_CLOCK_SYNC=0 if sync causes problems.
        """

    package enum Reason: String, Sendable {
        case wake
        case afterUp
        case commandEntry
    }

    package struct Result: Sendable {
        package let succeeded: Int
        package let failed: Int
    }

    /// Reconcile guest clocks for all running compose-managed workloads.
    package static func syncComposeWorkloads(reason: Reason) async -> Result {
        guard ClockSyncConfiguration.sessionEnabled else {
            return Result(succeeded: 0, failed: 0)
        }
        let targets: ClockSyncDiscovery.Targets
        do {
            targets = try await discoverTargets()
        } catch {
            logSyncFinished(reason: reason, succeeded: 0, failed: 0, discoveryFailed: true)
            emitFailureWarning()
            return Result(succeeded: 0, failed: 0)
        }
        guard !targets.isEmpty else {
            return Result(succeeded: 0, failed: 0)
        }
        logSyncStarted(reason: reason, hostCount: targets.hostContainerIDs.count,
                       machineCount: targets.machineHypervisorIDs.count)
        let containerIDs = targets.hostContainerIDs + targets.machineHypervisorIDs
        let result = await syncContainerIDs(containerIDs)
        logSyncFinished(
            reason: reason,
            succeeded: result.succeeded,
            failed: result.failed,
            discoveryFailed: false
        )
        if result.failed > 0 {
            emitFailureWarning()
        }
        return result
    }

    package static func discoverTargets() async throws -> ClockSyncDiscovery.Targets {
        let client = ContainerClient()
        let filters = ContainerListFilters(
            status: .running,
            labels: [ComposeLabels.project: ClockSyncDiscovery.projectLabelPattern]
        ).withoutMachines()
        let hostSnapshots = try await client.list(filters: filters)
        let hostIDs = ClockSyncDiscovery.hostContainerIDs(from: hostSnapshots)

        let machineClient = MachineClient()
        let machines = try await machineClient.list()
        var inVMByMachine: [String: [ManagedContainer]] = [:]
        var machineListFailures = 0
        for machine in machines where MachineContext.isRunning(machine) {
            do {
                inVMByMachine[machine.id] = try await MachineInVMRunner.listContainers(snapshot: machine)
            } catch {
                machineListFailures += 1
                continue
            }
        }
        if machineListFailures > 0 {
            fputs(
                "Warning: couldn't list containers in \(machineListFailures) machine(s) for clock sync.\n",
                stderr
            )
        }
        let hypervisorIDs = ClockSyncDiscovery.machineHypervisorIDs(
            machines: machines,
            inVMContainers: inVMByMachine
        )
        return ClockSyncDiscovery.Targets(
            hostContainerIDs: hostIDs,
            machineHypervisorIDs: hypervisorIDs
        )
    }

    private static let syncOperationTimeout: Duration = .seconds(10)

    private struct SyncTimedOut: Error {}

    private static func syncContainerIDs(_ ids: [String]) async -> Result {
        guard !ids.isEmpty else { return Result(succeeded: 0, failed: 0) }
        let eventLoopGroup = MultiThreadedEventLoopGroup(
            numberOfThreads: max(1, min(4, ids.count))
        )
        let result = await withTaskGroup(of: Bool.self) { taskGroup in
            for id in ids {
                taskGroup.addTask {
                    do {
                        try await syncContainer(id: id, eventLoopGroup: eventLoopGroup)
                        return true
                    } catch {
                        return false
                    }
                }
            }
            var succeeded = 0
            var failed = 0
            for await didSucceed in taskGroup {
                if didSucceed { succeeded += 1 } else { failed += 1 }
            }
            return Result(succeeded: succeeded, failed: failed)
        }
        try? await eventLoopGroup.shutdownGracefully()
        return result
    }

    private static func syncContainer(id: String, eventLoopGroup: EventLoopGroup) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                let client = ContainerClient()
                let handle = try await client.dial(id: id, port: Vminitd.port)
                let agent = try Vminitd(connection: handle, group: eventLoopGroup)
                do {
                    var hostTime = timeval()
                    guard gettimeofday(&hostTime, nil) == 0 else {
                        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EINVAL)
                    }
                    try await agent.setTime(
                        sec: Int64(hostTime.tv_sec),
                        usec: Int32(hostTime.tv_usec)
                    )
                    try await agent.close()
                } catch {
                    try? await agent.close()
                    throw error
                }
            }
            group.addTask {
                try await Task.sleep(for: syncOperationTimeout)
                throw SyncTimedOut()
            }
            guard try await group.next() != nil else {
                throw SyncTimedOut()
            }
            group.cancelAll()
        }
    }

    private static func emitFailureWarning() {
        fputs("\(failureWarning)\n", stderr)
    }

    private static func logSyncStarted(reason: Reason, hostCount: Int, machineCount: Int) {
        OsLogTelemetry.enabled {
            OsLogTelemetry.lifecycle.info(
                """
                event=clock_sync_started reason=\(reason.rawValue, privacy: .public) \
                host_targets=\(hostCount, privacy: .public) \
                machine_targets=\(machineCount, privacy: .public)
                """
            )
        }
    }

    private static func logSyncFinished(
        reason: Reason,
        succeeded: Int,
        failed: Int,
        discoveryFailed: Bool
    ) {
        OsLogTelemetry.enabled {
            OsLogTelemetry.lifecycle.info(
                """
                event=clock_sync_finished reason=\(reason.rawValue, privacy: .public) \
                succeeded=\(succeeded, privacy: .public) failed=\(failed, privacy: .public) \
                discovery_failed=\(discoveryFailed, privacy: .public)
                """
            )
        }
    }
}
