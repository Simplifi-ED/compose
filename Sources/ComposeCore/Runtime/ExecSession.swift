import ArgumentParser
import ContainerAPIClient
import ContainerResource
import Foundation
import Logging

/// Foreground exec session: PTY/stdin via upstream `ProcessIO`, interrupt via `SignalForwarding`.
package enum ExecSession {
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

    package struct Configuration: Sendable {
        package let containerName: String
        package let projectName: String
        package let executable: String
        package let arguments: [String]
        package let processTerminal: Bool
        package let interactive: Bool
        package let useInteractivePTY: Bool

        package init(
            containerName: String,
            projectName: String,
            executable: String,
            arguments: [String],
            processTerminal: Bool,
            interactive: Bool,
            useInteractivePTY: Bool
        ) {
            self.containerName = containerName
            self.projectName = projectName
            self.executable = executable
            self.arguments = arguments
            self.processTerminal = processTerminal
            self.interactive = interactive
            self.useInteractivePTY = useInteractivePTY
        }
    }

    package typealias ExecBody = @Sendable (
        Configuration,
        IOHolder,
        @Sendable (String) async throws -> ContainerSnapshot,
        @Sendable (String, String, ProcessConfiguration, [FileHandle?]) async throws -> any ClientProcess
    ) async throws -> Int32

    package final class IOHolder: @unchecked Sendable {
        package var processIO: ProcessIO?

        package init() {}
    }

    private final class ExitCodeHolder: @unchecked Sendable {
        var value: Int32 = 0
    }

    package static func run(
        configuration: Configuration,
        shutdownContext: ProjectShutdownContext,
        getContainer: @escaping @Sendable (String) async throws -> ContainerSnapshot = { id in
            try await ContainerClient().get(id: id)
        },
        createProcess: @escaping @Sendable (
            String,
            String,
            ProcessConfiguration,
            [FileHandle?]
        ) async throws -> any ClientProcess = { containerId, processId, config, stdio in
            try await ContainerClient().createProcess(
                containerId: containerId,
                processId: processId,
                configuration: config,
                stdio: stdio
            )
        },
        execBody: @escaping ExecBody = runExecBody,
        stopProject: @escaping @Sendable (ProjectShutdownContext) async throws -> Void = {
            try await ProjectShutdown.stop(context: $0)
        }
    ) async throws {
        let holder = IOHolder()
        let exitHolder = ExitCodeHolder()

        let outcome = try await SignalForwarding.runUntilCancelled(
            policy: .stopProject(shutdownContext),
            terminalCleanup: {
                try? holder.processIO?.close()
            },
            stopProject: stopProject,
            body: {
                exitHolder.value = try await execBody(
                    configuration,
                    holder,
                    getContainer,
                    createProcess
                )
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

    package static func runExecBody(
        configuration: Configuration,
        holder: IOHolder,
        getContainer: @Sendable (String) async throws -> ContainerSnapshot,
        createProcess: @Sendable (
            String,
            String,
            ProcessConfiguration,
            [FileHandle?]
        ) async throws -> any ClientProcess
    ) async throws -> Int32 {
        let snapshot = try await getContainer(configuration.containerName)
        try verifyProjectLabel(snapshot: snapshot, configuration: configuration)

        var processConfig = snapshot.configuration.initProcess
        processConfig.executable = configuration.executable
        processConfig.arguments = configuration.arguments
        processConfig.terminal = configuration.processTerminal

        let processIO = try ProcessIO.create(
            tty: configuration.useInteractivePTY,
            interactive: configuration.interactive,
            detach: false
        )
        holder.processIO = processIO
        defer {
            try? processIO.close()
        }

        let process = try await createProcess(
            configuration.containerName,
            UUID().uuidString.lowercased(),
            processConfig,
            processIO.stdio
        )

        if configuration.useInteractivePTY {
            let log = Logger(label: "compose.exec")
            return try await processIO.handleProcess(process: process, log: log)
        }

        return try await runNonTTYProcess(process: process, processIO: processIO)
    }

    package static func verifyExecTarget(
        snapshot: ContainerSnapshot,
        configuration: Configuration
    ) throws {
        try verifyProjectLabel(snapshot: snapshot, configuration: configuration)
    }

    private static func verifyProjectLabel(
        snapshot: ContainerSnapshot,
        configuration: Configuration
    ) throws {
        let labelProject = snapshot.configuration.labels[ComposeLabels.project]
        guard labelProject == configuration.projectName else {
            throw ComposeError.containerProjectMismatch(
                container: configuration.containerName,
                project: configuration.projectName
            )
        }
        guard snapshot.status == .running else {
            throw ComposeError.serviceNotRunning(
                service: snapshot.configuration.labels[ComposeLabels.service] ?? configuration.containerName,
                state: ProjectStatus.formatState(snapshot.status)
            )
        }
    }

    /// Non-TTY path: stream I/O without `ProcessIO` SIGINT/SIGTERM forwarding (compose owns interrupts).
    private static func runNonTTYProcess(process: any ClientProcess, processIO: ProcessIO) async throws -> Int32 {
        try await process.start()
        try processIO.closeAfterStart()
        async let exitCode = process.wait()
        try await processIO.wait()
        return try await exitCode
    }
}
