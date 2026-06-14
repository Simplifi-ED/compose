import Foundation

package struct DoctorSubprocessResult: Sendable, Equatable {
    package let exitCode: Int32
    package let stdout: String
    package let stderr: String

    package init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

package enum DoctorSubprocessError: Error, Sendable, Equatable {
    case executableNotFound(String)
    case timedOut(String)
}

package enum DoctorSubprocess {
    package static func runCapturing(
        executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        timeout: Duration = DoctorRequirements.subprocessTimeout
    ) async throws -> DoctorSubprocessResult {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw DoctorSubprocessError.executableNotFound(executable)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment {
            var merged = ProcessInfo.processInfo.environment
            for (key, value) in environment {
                merged[key] = value
            }
            process.environment = merged
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutReader = Task { @concurrent in
            stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        }
        let stderrReader = Task { @concurrent in
            stderrPipe.fileHandleForReading.readDataToEndOfFile()
        }

        try process.run()
        let exitCode = try await waitForExit(process: process, executable: executable, timeout: timeout)
        closePipes(stdoutPipe: stdoutPipe, stderrPipe: stderrPipe)

        let stdoutData = await stdoutReader.value
        let stderrData = await stderrReader.value
        return DoctorSubprocessResult(
            exitCode: exitCode,
            stdout: String(bytes: stdoutData, encoding: .utf8) ?? "",
            stderr: String(bytes: stderrData, encoding: .utf8) ?? ""
        )
    }

    package static func which(
        _ command: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async -> String? {
        for directory in pathEntries(from: environment) {
            let candidate = (directory as NSString).appendingPathComponent(command)
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    package static func pathEntries(from environment: [String: String]) -> [String] {
        guard let path = environment["PATH"], !path.isEmpty else { return [] }
        return path.split(separator: ":").map(String.init)
    }

    private static func waitForExit(
        process: Process,
        executable: String,
        timeout: Duration
    ) async throws -> Int32 {
        do {
            return try await withThrowingTaskGroup(of: Int32.self) { group in
                group.addTask {
                    process.waitUntilExit()
                    return process.terminationStatus
                }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw DoctorSubprocessError.timedOut(executable)
                }
                guard let code = try await group.next() else {
                    throw DoctorSubprocessError.timedOut(executable)
                }
                group.cancelAll()
                return code
            }
        } catch {
            process.terminate()
            throw error
        }
    }

    private static func closePipes(stdoutPipe: Pipe, stderrPipe: Pipe) {
        try? stdoutPipe.fileHandleForWriting.close()
        try? stderrPipe.fileHandleForWriting.close()
        try? stdoutPipe.fileHandleForReading.close()
        try? stderrPipe.fileHandleForReading.close()
    }
}
