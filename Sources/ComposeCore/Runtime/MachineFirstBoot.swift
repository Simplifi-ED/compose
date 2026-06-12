import ContainerAPIClient
import ContainerResource
import Foundation
import MachineAPIClient

/// Runs the in-VM user provisioning step on first boot (non-interactive).
enum MachineFirstBoot {
    static func runUserSetup(snapshot: MachineSnapshot) async throws {
        guard !snapshot.initialized else { return }
        guard let containerId = snapshot.containerId else {
            throw ComposeError.machineNotRunning(snapshot.id)
        }

        let processConfig = ProcessConfiguration(
            executable: "/\(MachineBundle.sbinDirectory)/\(MachineBundle.initFile)",
            arguments: ["-u"],
            environment: snapshot.configuration.processEnvironment,
            terminal: false
        )

        let stderrPipe = Pipe()
        let process = try await ContainerClient().createProcess(
            containerId: containerId,
            processId: UUID().uuidString.lowercased(),
            configuration: processConfig,
            stdio: [nil, nil, stderrPipe.fileHandleForWriting]
        )
        try await process.start()
        let exitCode = try await process.wait()
        guard exitCode == 0 else {
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let detail = String(bytes: errData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let reason = detail.isEmpty ? "exit \(exitCode)" : detail
            let underlying = ComposeError.invalidField("machine user setup", reason: reason)
            throw ComposeError.machineBootFailed(snapshot.id, underlying: underlying)
        }
    }
}
