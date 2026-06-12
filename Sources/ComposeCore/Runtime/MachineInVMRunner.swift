import ContainerAPIClient
import ContainerResource
import Foundation
import Logging
import MachineAPIClient

/// Runs `container` CLI commands inside a booted container machine via `createProcess`.
enum MachineInVMRunner {
    struct CommandCapture: Sendable {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    private static let initExecutable = "/\(MachineBundle.sbinDirectory)/\(MachineBundle.initFile)"

    static func run(
        snapshot: MachineSnapshot,
        containerArguments: [String]
    ) async throws {
        let capture = try await runCapturing(
            snapshot: snapshot,
            containerArguments: containerArguments
        )
        guard capture.exitCode == 0 else {
            forwardStderr(capture.stderr)
            throw ComposeError.machineCommandFailed(
                machine: snapshot.id,
                command: (["container"] + containerArguments).joined(separator: " "),
                exitCode: capture.exitCode
            )
        }
    }

    private static func forwardStderr(_ text: String) {
        guard !text.isEmpty else { return }
        fputs(text, stderr)
        if !text.hasSuffix("\n") {
            fputs("\n", stderr)
        }
    }

    static func runCapturing(
        snapshot: MachineSnapshot,
        containerArguments: [String]
    ) async throws -> CommandCapture {
        guard let containerId = snapshot.containerId else {
            throw ComposeError.machineNotRunning(snapshot.id)
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let processConfig = ProcessConfiguration(
            executable: initExecutable,
            arguments: ["-s", "container"] + containerArguments,
            environment: snapshot.configuration.processEnvironment,
            terminal: false
        )

        let process = try await ContainerClient().createProcess(
            containerId: containerId,
            processId: UUID().uuidString.lowercased(),
            configuration: processConfig,
            stdio: [nil, stdoutPipe.fileHandleForWriting, stderrPipe.fileHandleForWriting]
        )
        let stdoutReader = Task { @concurrent in
            stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        }
        let stderrReader = Task { @concurrent in
            stderrPipe.fileHandleForReading.readDataToEndOfFile()
        }
        try await process.start()
        let exitCode = try await process.wait()
        try? stdoutPipe.fileHandleForWriting.close()
        try? stderrPipe.fileHandleForWriting.close()
        let stdoutData = await stdoutReader.value
        let stderrData = await stderrReader.value
        try? stdoutPipe.fileHandleForReading.close()
        try? stderrPipe.fileHandleForReading.close()
        let stdout = String(bytes: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(bytes: stderrData, encoding: .utf8) ?? ""
        return CommandCapture(exitCode: exitCode, stdout: stdout, stderr: stderr)
    }

    static func runInteractive(
        snapshot: MachineSnapshot,
        containerArguments: [String],
        processIO: ProcessIO,
        useInteractivePTY: Bool,
        log: Logger
    ) async throws -> Int32 {
        guard let containerId = snapshot.containerId else {
            throw ComposeError.machineNotRunning(snapshot.id)
        }

        let processConfig = ProcessConfiguration(
            executable: initExecutable,
            arguments: ["-s", "container"] + containerArguments,
            environment: snapshot.configuration.processEnvironment,
            terminal: useInteractivePTY
        )

        let process = try await ContainerClient().createProcess(
            containerId: containerId,
            processId: UUID().uuidString.lowercased(),
            configuration: processConfig,
            stdio: processIO.stdio
        )
        return try await InteractiveSession.waitForProcess(
            process: process,
            processIO: processIO,
            useInteractivePTY: useInteractivePTY,
            log: log
        )
    }

    static func streamContainerOutput(
        snapshot: MachineSnapshot,
        containerArguments: [String]
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let runTask = Task {
                do {
                    try await pumpStreamedContainerOutput(
                        snapshot: snapshot,
                        containerArguments: containerArguments,
                        continuation: continuation
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                runTask.cancel()
            }
        }
    }

    private static func pumpStreamedContainerOutput(
        snapshot: MachineSnapshot,
        containerArguments: [String],
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let readHandle = stdoutPipe.fileHandleForReading
        let stderrReadHandle = stderrPipe.fileHandleForReading
        defer {
            readHandle.readabilityHandler = nil
            try? stdoutPipe.fileHandleForWriting.close()
            try? stderrPipe.fileHandleForWriting.close()
            try? readHandle.close()
            try? stderrReadHandle.close()
        }

        guard let containerId = snapshot.containerId else {
            throw ComposeError.machineNotRunning(snapshot.id)
        }

        let processConfig = ProcessConfiguration(
            executable: initExecutable,
            arguments: ["-s", "container"] + containerArguments,
            environment: snapshot.configuration.processEnvironment,
            terminal: false
        )

        let process = try await ContainerClient().createProcess(
            containerId: containerId,
            processId: UUID().uuidString.lowercased(),
            configuration: processConfig,
            stdio: [nil, stdoutPipe.fileHandleForWriting, stderrPipe.fileHandleForWriting]
        )

        readHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                continuation.yield(text)
            }
        }

        try await process.start()
        let exitCode = try await process.wait()
        readHandle.readabilityHandler = nil

        yieldUTF8Chunk(from: readHandle.readDataToEndOfFile(), continuation: continuation)

        let stderrText = String(bytes: stderrReadHandle.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard exitCode == 0 else {
            forwardStderr(stderrText)
            throw ComposeError.machineCommandFailed(
                machine: snapshot.id,
                command: (["container"] + containerArguments).joined(separator: " "),
                exitCode: exitCode
            )
        }
    }

    private static func yieldUTF8Chunk(
        from data: Data,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) {
        guard !data.isEmpty,
              let text = String(data: data, encoding: .utf8),
              !text.isEmpty else { return }
        continuation.yield(text)
    }

    static func listContainers(snapshot: MachineSnapshot, all: Bool = true) async throws -> [ManagedContainer] {
        var args = ["list", "--format", "json"]
        if all {
            args.append("--all")
        }
        let result = try await runCapturing(snapshot: snapshot, containerArguments: args)
        guard result.exitCode == 0 else {
            throw ComposeError.machineCommandFailed(
                machine: snapshot.id,
                command: "container list --format json",
                exitCode: result.exitCode
            )
        }
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return try JSONDecoder().decode([ManagedContainer].self, from: Data(trimmed.utf8))
    }
}
