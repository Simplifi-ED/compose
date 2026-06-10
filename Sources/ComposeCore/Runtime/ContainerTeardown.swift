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
    public static func teardown(id: String) async throws {
        try await ignoringNotFound {
            try await stop(id: id)
        }
        try await ignoringNotFound {
            try await delete(id: id)
        }
    }

    /// Stops and removes a container, force-removing on task cancellation.
    package static func teardownRespectingCancellation(
        id: String,
        perform: (@Sendable () async throws -> Void)? = nil
    ) async throws {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            if let perform {
                try await perform()
            } else {
                try await teardown(id: id)
            }
        } onCancel: {
            Task {
                await forceRemoveAfterInterrupt(id: id)
            }
        }
    }

    /// Runs a detached `ContainerRun`, removing the container on task cancellation.
    package static func runDetachedContainerRespectingCancellation(
        containerName: String,
        run: @Sendable @escaping () async throws -> Void
    ) async throws {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await run()
        } onCancel: {
            Task {
                await forceRemoveAfterInterrupt(id: containerName)
            }
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

    package static func stopGracefully(id: String, options: GracefulStopOptions) async throws {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await stopGracefullyUnchecked(id: id, options: options)
        } onCancel: {
            Task {
                await forceRemoveAfterInterrupt(id: id)
            }
        }
    }

    private static func stopGracefullyUnchecked(id: String, options: GracefulStopOptions) async throws {
        let client = ContainerClient()
        let stopOptions = stopOptions(for: options)
        do {
            try await client.stop(id: id, opts: stopOptions)
        } catch let stopError {
            if isIgnorableError(stopError) {
                return
            }
            // Graceful stop API failed; force-kill immediately instead of waiting again.
            do {
                try await client.kill(id: id, signal: "SIGKILL")
            } catch {
                if isIgnorableError(error) {
                    return
                }
                throw stopError
            }
        }
    }

    private static func forceRemoveAfterInterrupt(id: String) async {
        let client = ContainerClient()
        try? await client.kill(id: id, signal: "SIGKILL")
        try? await ignoringNotFound {
            try await client.delete(id: id, force: true)
        }
    }

    private static func stop(id: String) async throws {
        let client = ContainerClient()
        try await client.stop(id: id)
    }

    private static func delete(id: String) async throws {
        let client = ContainerClient()
        try await client.delete(id: id, force: true)
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
