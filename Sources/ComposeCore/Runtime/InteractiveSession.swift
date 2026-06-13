import ArgumentParser
import ContainerAPIClient
import ContainerResource
import ContainerizationOS
import Darwin
import Foundation
import Logging

/// Shared interactive I/O for foreground sessions (`exec`, future attach paths).
package enum InteractiveSession {
    package struct IOFlags: Sendable, Equatable {
        package let interactive: Bool
        package let processTerminal: Bool
        package let useInteractivePTY: Bool

        package static func resolve(
            explicitInteractive: Bool,
            explicitTTY: Bool,
            stdinIsTTY: Bool
        ) -> IOFlags {
            let interactive = explicitInteractive || stdinIsTTY
            let processTerminal = explicitTTY || stdinIsTTY
            let useInteractivePTY = processTerminal && interactive && stdinIsTTY
            return IOFlags(
                interactive: interactive,
                processTerminal: processTerminal,
                useInteractivePTY: useInteractivePTY
            )
        }
    }

    /// Holds `ProcessIO` for terminal cleanup on interrupt; single-owner before await.
    package final class IOHolder: @unchecked Sendable {
        package var processIO: ProcessIO?

        package init() {}
    }

    /// Captures stdin termios before upstream `ContainerRun` enters raw mode for restore on interrupt.
    package final class StdinRestoreHandle: @unchecked Sendable {
        private let terminal: Terminal?

        package init(useInteractivePTY: Bool) {
            if useInteractivePTY, isatty(STDIN_FILENO) == 1 {
                terminal = try? Terminal(descriptor: STDIN_FILENO)
            } else {
                terminal = nil
            }
        }

        package func restore() {
            terminal?.tryReset()
        }
    }

    package static func createProcessIO(
        interactive: Bool,
        useInteractivePTY: Bool
    ) throws -> ProcessIO {
        try ProcessIO.create(
            tty: useInteractivePTY,
            interactive: interactive,
            detach: false
        )
    }

    /// Waits for a foreground process to exit.
    /// Interactive PTY (`useInteractivePTY`): upstream `ProcessIO.handleProcess` forwards SIGWINCH
    /// to `ClientProcess.resize` and owns raw-mode terminal I/O. Compose owns SIGINT/SIGTERM via
    /// `SignalForwarding` in `runUntilExit`.
    package static func waitForProcess(
        process: any ClientProcess,
        processIO: ProcessIO,
        useInteractivePTY: Bool,
        log: Logger
    ) async throws -> Int32 {
        if useInteractivePTY {
            return try await processIO.handleProcess(process: process, log: log)
        }
        return try await waitNonTTY(process: process, processIO: processIO)
    }

    /// Non-TTY path: stream I/O without `ProcessIO` SIGINT/SIGTERM forwarding (compose owns interrupts).
    package static func waitNonTTY(
        process: any ClientProcess,
        processIO: ProcessIO
    ) async throws -> Int32 {
        try await process.start()
        try processIO.closeAfterStart()
        async let exitCode = process.wait()
        try await processIO.wait()
        return try await exitCode
    }

    package static func runUntilExit(
        policy: InterruptPolicy,
        terminalCleanup: @Sendable () async -> Void = {},
        stopProject: @Sendable (ProjectShutdownContext) async throws -> Void = {
            try await ProjectShutdown.stop(context: $0)
        },
        stopRunContainer: @Sendable (RunShutdownContext) async throws -> Void = {
            try await RunShutdownContext.stopAndRemove(context: $0)
        },
        body: @escaping @Sendable () async throws -> Int32
    ) async throws {
        let exitHolder = ExitCodeHolder()
        let outcome = try await SignalForwarding.runUntilCancelled(
            policy: policy,
            terminalCleanup: terminalCleanup,
            stopProject: stopProject,
            stopRunContainer: stopRunContainer,
            body: {
                exitHolder.value = try await body()
            }
        )
        switch outcome {
        case .completed:
            throw ExitCode(exitHolder.value)
        case .interrupted(let signal):
            throw ExitCode(signal.exitCode)
        case .cancelledQuietly:
            throw ExitCode(0)
        }
    }

    private final class ExitCodeHolder: @unchecked Sendable {
        var value: Int32 = 0
    }
}
