import ContainerAPIClient
import ContainerResource
import Foundation
import Logging
import MachineAPIClient

/// Runs `container` CLI commands inside a booted container machine via `createProcess`.
enum MachineInVMRunner {
    private final class OutputBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var text = ""

        func append(_ chunk: String) {
            lock.lock()
            defer { lock.unlock() }
            text += chunk
        }

        var value: String {
            lock.lock()
            defer { lock.unlock() }
            return text
        }
    }

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
        let exitCode = try await runCapturing(snapshot: snapshot, containerArguments: containerArguments).exitCode
        guard exitCode == 0 else {
            throw ComposeError.machineCommandFailed(
                machine: snapshot.id,
                command: (["container"] + containerArguments).joined(separator: " "),
                exitCode: exitCode
            )
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
        try await process.start()
        let exitCode = try await process.wait()
        try? stdoutPipe.fileHandleForWriting.close()
        try? stderrPipe.fileHandleForWriting.close()
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
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
    ) async throws -> String {
        guard let containerId = snapshot.containerId else {
            throw ComposeError.machineNotRunning(snapshot.id)
        }

        let stdoutPipe = Pipe()
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
            stdio: [nil, stdoutPipe.fileHandleForWriting, nil]
        )
        try await process.start()

        let readHandle = stdoutPipe.fileHandleForReading
        let output = OutputBuffer()
        readHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                output.append(text)
            }
        }

        defer {
            readHandle.readabilityHandler = nil
            try? stdoutPipe.fileHandleForWriting.close()
            try? readHandle.close()
        }

        _ = try await process.wait()
        return output.value
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
