import ArgumentParser
import ContainerAPIClient
import ContainerResource
import Foundation
import Logging

/// Foreground exec session: in-container process via `createProcess`, interrupt via `SignalForwarding`.
package enum ExecSession {
    package typealias IOFlags = InteractiveSession.IOFlags
    package typealias IOHolder = InteractiveSession.IOHolder

    package struct Configuration: Sendable {
        package let containerName: String
        package let projectName: String
        package let serviceName: String
        package let executable: String
        package let arguments: [String]
        package let processTerminal: Bool
        package let interactive: Bool
        package let useInteractivePTY: Bool

        package init(
            containerName: String,
            projectName: String,
            serviceName: String,
            executable: String,
            arguments: [String],
            processTerminal: Bool,
            interactive: Bool,
            useInteractivePTY: Bool
        ) {
            self.containerName = containerName
            self.projectName = projectName
            self.serviceName = serviceName
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

    package static func run(
        configuration: Configuration,
        shutdownContext: ProjectShutdownContext,
        getContainer: @escaping @Sendable (String) async throws -> ContainerSnapshot = ContainerCopyAPI.get,
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
        try await InteractiveSession.runUntilExit(
            policy: .stopProject(shutdownContext),
            terminalCleanup: {
                try? holder.processIO?.close()
            },
            stopProject: stopProject,
            body: {
                try await execBody(
                    configuration,
                    holder,
                    getContainer,
                    createProcess
                )
            }
        )
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
        try verifyExecTarget(snapshot: snapshot, configuration: configuration)

        var processConfig = snapshot.configuration.initProcess
        processConfig.executable = configuration.executable
        processConfig.arguments = configuration.arguments
        processConfig.terminal = configuration.processTerminal

        let processIO = try InteractiveSession.createProcessIO(
            interactive: configuration.interactive,
            useInteractivePTY: configuration.useInteractivePTY
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

        let log = Logger(label: "compose.exec")
        return try await InteractiveSession.waitForProcess(
            process: process,
            processIO: processIO,
            useInteractivePTY: configuration.useInteractivePTY,
            log: log
        )
    }

    package static func verifyExecTarget(
        snapshot: ContainerSnapshot,
        configuration: Configuration
    ) throws {
        try ComposeContainerGuard.verifyRunningProjectService(
            snapshot: snapshot,
            containerName: configuration.containerName,
            projectName: configuration.projectName,
            serviceName: configuration.serviceName,
            fieldName: "exec"
        )
    }
}
