import ContainerAPIClient
import Foundation

/// Waits for a detached container's init process to exit and returns its exit code.
///
/// Uses `ContainerClient.bootstrap` to obtain a wait handle on an already-running container,
/// then blocks on `ClientProcess.wait()` (XPC `containerWait` on the init process).
package enum InitExitWait {
    package struct TimedOut: Error {
        package init() {}
    }

    package typealias ExitCodeProvider = @Sendable (String) async throws -> Int32

    private static let defaultExitTimeout: Duration = .seconds(60)

    package static func waitForInitExit(
        containerId: String,
        timeout: Duration = defaultExitTimeout,
        machineContext: MachineContext = .applicationSandbox
    ) async throws -> Int32 {
        if machineContext.isMachineMode {
            throw ComposeError.machineUnsupportedOperation(
                "depends_on condition service_completed_successfully"
            )
        }
        return try await withThrowingTaskGroup(of: Int32.self) { group in
            group.addTask {
                let client = ContainerClient()
                let process = try await client.bootstrap(id: containerId, stdio: [nil, nil, nil])
                return try await process.wait()
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw TimedOut()
            }
            guard let exitCode = try await group.next() else {
                throw TimedOut()
            }
            group.cancelAll()
            return exitCode
        }
    }

    package static func exitCodeProvider(
        machineContext: MachineContext = .applicationSandbox,
        timeout: Duration = defaultExitTimeout
    ) -> ExitCodeProvider {
        { containerId in
            try await waitForInitExit(
                containerId: containerId,
                timeout: timeout,
                machineContext: machineContext
            )
        }
    }
}
