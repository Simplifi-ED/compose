import ContainerAPIClient
import ContainerCommands
import ContainerizationError
import ContainerResource
import Foundation

/// Grace period after SIGTERM before SIGKILL when stopping containers.
package struct GracefulStopOptions: Sendable {
    package static let defaultGraceSeconds: Int32 = 10

    package let graceSeconds: Int32

    package init(graceSeconds: Int32 = Self.defaultGraceSeconds) {
        self.graceSeconds = graceSeconds
    }
}

public enum ContainerTeardown {
    public static func teardown(
        id: String,
        machineContext: MachineContext = .applicationSandbox
    ) async throws {
        try await ignoringNotFound {
            try await stop(id: id, machineContext: machineContext)
        }
        try await ignoringNotFound {
            try await delete(id: id, machineContext: machineContext)
        }
    }

    /// Stops and removes a container, force-removing on task cancellation.
    package static func teardownRespectingCancellation(
        id: String,
        machineContext: MachineContext = .applicationSandbox
    ) async throws {
        try await teardownRespectingCancellation(id: id, machineContext: machineContext) {
            try await teardown(id: id, machineContext: machineContext)
        }
    }

    /// Runs container work, force-removing `id` on task cancellation.
    package static func teardownRespectingCancellation(
        id: String,
        machineContext: MachineContext = .applicationSandbox,
        perform: @escaping @Sendable () async throws -> Void
    ) async throws {
        try await withInterruptCleanup(id: id, machineContext: machineContext) {
            try Task.checkCancellation()
            try await perform()
        }
    }

    public static func isIgnorableError(_ error: Error) -> Bool {
        if let error = error as? ContainerizationError {
            if error.isCode(.notFound) {
                return true
            }
            if let cause = error.cause {
                return isIgnorableError(cause)
            }
            return false
        }
        if let composeError = error as? ComposeError {
            if case .serviceNotFound = composeError {
                return true
            }
        }
        if let aggregate = error as? AggregateError {
            return !aggregate.errors.isEmpty
                && aggregate.errors.allSatisfy { isIgnorableError($0) }
        }
        return false
    }

    /// Sends SIGTERM, waits `options.graceSeconds`, then SIGKILL if still running.
    package static func stopOptions(for options: GracefulStopOptions) -> ContainerStopOptions {
        ContainerStopOptions(
            timeoutInSeconds: options.graceSeconds,
            signal: "SIGTERM"
        )
    }

    package static func stopGracefully(
        id: String,
        options: GracefulStopOptions,
        machineContext: MachineContext = .applicationSandbox
    ) async throws {
        try await withInterruptCleanup(id: id, machineContext: machineContext, onInterrupt: forceKillAfterInterrupt) {
            try Task.checkCancellation()
            try await stopGracefullyUnchecked(id: id, options: options, machineContext: machineContext)
        }
    }

    private static func withInterruptCleanup(
        id: String,
        machineContext: MachineContext = .applicationSandbox,
        onInterrupt: @escaping @Sendable (String, MachineContext) async -> Void = forceRemoveAfterInterrupt,
        _ body: @escaping @Sendable () async throws -> Void
    ) async throws {
        try await withTaskCancellationHandler {
            try await body()
        } onCancel: {
            Task {
                await onInterrupt(id, machineContext)
            }
        }
    }

    private static func stopGracefullyUnchecked(
        id: String,
        options: GracefulStopOptions,
        machineContext: MachineContext
    ) async throws {
        let stopOptions = stopOptions(for: options)
        do {
            try await ComposeContainerGateway.stop(id: id, opts: stopOptions, machineContext: machineContext)
        } catch let stopError {
            if isIgnorableError(stopError) {
                return
            }
            do {
                try await ComposeContainerGateway.kill(
                    id: id,
                    signal: "SIGKILL",
                    machineContext: machineContext
                )
            } catch {
                if isIgnorableError(error) {
                    return
                }
                throw stopError
            }
        }
    }

    private static func forceKillAfterInterrupt(id: String, machineContext: MachineContext) async {
        try? await ComposeContainerGateway.kill(
            id: id,
            signal: "SIGKILL",
            machineContext: machineContext
        )
    }

    private static func forceRemoveAfterInterrupt(id: String, machineContext: MachineContext) async {
        try? await ComposeContainerGateway.kill(
            id: id,
            signal: "SIGKILL",
            machineContext: machineContext
        )
        try? await ignoringNotFound {
            try await ComposeContainerGateway.delete(
                id: id,
                force: true,
                machineContext: machineContext
            )
        }
    }

    private static func stop(
        id: String,
        machineContext: MachineContext
    ) async throws {
        try await ComposeContainerGateway.stop(id: id, machineContext: machineContext)
    }

    private static func delete(
        id: String,
        machineContext: MachineContext
    ) async throws {
        try await ComposeContainerGateway.delete(id: id, machineContext: machineContext)
    }

    private static func ignoringNotFound(_ body: () async throws -> Void) async throws {
        do {
            try await body()
        } catch {
            if !isIgnorableError(error) {
                throw error
            }
        }
    }
}
