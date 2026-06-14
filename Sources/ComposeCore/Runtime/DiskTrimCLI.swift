import Foundation

/// Invokes the `container` CLI for privileged trim helpers (guest `fstrim` only).
enum DiskTrimCLI {
    struct Result: Sendable {
        let exitCode: Int32
        let stderr: String
    }

    static func resolveContainerPath() async -> String? {
        await DoctorSubprocess.which("container")
    }

    static func run(
        containerPath: String,
        arguments: [String],
        timeout: Duration = .seconds(120)
    ) async -> Result {
        do {
            let capture = try await DoctorSubprocess.runCapturing(
                executable: containerPath,
                arguments: arguments,
                timeout: timeout
            )
            return Result(exitCode: capture.exitCode, stderr: capture.stderr)
        } catch {
            return Result(exitCode: 1, stderr: error.localizedDescription)
        }
    }

    /// Privileged one-shot helper: `container run --rm --cap-add SYS_ADMIN -v <vol>:/mnt … fstrim -v /mnt`
    static func trimNamedVolume(
        containerPath: String,
        runtimeName: String,
        machineName: String?
    ) async -> Result {
        var arguments = ["run", "--rm", "--cap-add", "SYS_ADMIN", "-v", "\(runtimeName):/mnt"]
        if let machineName {
            arguments.insert(contentsOf: ["--machine", machineName], at: 1)
        }
        arguments.append(contentsOf: [
            DiskTrimHost.trimHelperImage,
            "fstrim", "-v", "/mnt"
        ])
        return await run(containerPath: containerPath, arguments: arguments)
    }

    static func startContainer(containerPath: String, id: String, machineName: String?) async -> Result {
        var arguments = ["start", id]
        if let machineName {
            arguments = ["--machine", machineName, "start", id]
        }
        return await run(containerPath: containerPath, arguments: arguments)
    }

    static func execFstrimRoot(containerPath: String, id: String, machineName: String?) async -> Result {
        var arguments = ["exec", id, "fstrim", "-v", "/"]
        if let machineName {
            arguments = ["--machine", machineName, "exec", id, "fstrim", "-v", "/"]
        }
        return await run(containerPath: containerPath, arguments: arguments)
    }
}
