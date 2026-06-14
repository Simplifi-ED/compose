import Darwin
import Foundation

extension HostsFileEditor {
    package static func apply(
        mergedContent: String,
        hostsPath: String = defaultHostsPath,
        requiresManagedBlock: Bool = true,
        privilegedApply: @escaping @Sendable (URL, String) throws -> Void = { tempURL, hostsPath in
            try defaultPrivilegedApply(tempURL: tempURL, hostsPath: hostsPath, operation: "install")
        }
    ) throws {
        let validated = try validatedContent(mergedContent, requiresManagedBlock: requiresManagedBlock)
        let tempURL = try writeTempFile(validated)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        if FileManager.default.isWritableFile(atPath: hostsPath) {
            try replaceHostsFile(from: tempURL, to: hostsPath)
            return
        }
        try privilegedApply(tempURL, hostsPath)
    }

    package static func readHostsFile(at path: String = defaultHostsPath) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    package static func withHostsLock<T>(
        _ body: () throws -> T
    ) throws -> T {
        // ponytail: advisory flock only coordinates compose instances; external editors can still race
        let lockURL = ComposeFileStaging.stagingRoot().appendingPathComponent("hosts.lock")
        try FileManager.default.createDirectory(
            at: ComposeFileStaging.stagingRoot(),
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: lockURL.path) {
            FileManager.default.createFile(atPath: lockURL.path, contents: Data())
        }
        let handle = try FileHandle(forWritingTo: lockURL)
        defer {
            flock(handle.fileDescriptor, LOCK_UN)
            try? handle.close()
        }
        while flock(handle.fileDescriptor, LOCK_EX) != 0 {
            if errno == EINTR { continue }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return try body()
    }

    package static func defaultPrivilegedApply(
        tempURL: URL,
        hostsPath: String,
        operation: String = "install"
    ) throws {
        guard isatty(STDERR_FILENO) == 1 else {
            throw ComposeError.hostDNSRequiresElevation(
                manualCommand: "sudo cp '\(tempURL.path)' '\(hostsPath)'"
            )
        }
        let escapedTemp = shellSingleQuote(tempURL.path)
        let escapedHosts = shellSingleQuote(hostsPath)
        let script =
            "do shell script \"cp \(escapedTemp) \(escapedHosts)\" with administrator privileges"
        let result = try runProcess(executable: "/usr/bin/osascript", arguments: ["-e", script])
        if result.exitCode != 0 {
            if result.stderr.localizedCaseInsensitiveContains("User canceled") {
                throw ComposeError.hostDNSElevationCancelled(operation: operation)
            }
            throw ComposeError.hostDNSRequiresElevation(
                manualCommand: "sudo cp '\(tempURL.path)' '\(hostsPath)'"
            )
        }
    }

    static func validatedContent(_ content: String, requiresManagedBlock: Bool = true) throws -> String {
        guard !content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty else {
            throw ComposeError.invalidField("/etc/hosts", reason: "refusing to write an empty hosts file")
        }
        if requiresManagedBlock, !content.contains("# BEGIN container-compose:") {
            throw ComposeError.invalidField("/etc/hosts", reason: "merged content is missing a container-compose block")
        }
        return content.hasSuffix("\n") ? content : content + "\n"
    }

    static func writeTempFile(_ content: String) throws -> URL {
        let url = ComposeFileStaging.stagingRoot()
            .appendingPathComponent("hosts-\(ProcessInfo.processInfo.processIdentifier).tmp")
        try FileManager.default.createDirectory(
            at: ComposeFileStaging.stagingRoot(),
            withIntermediateDirectories: true
        )
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func replaceHostsFile(from tempURL: URL, to hostsPath: String) throws {
        let destination = URL(fileURLWithPath: hostsPath)
        _ = try FileManager.default.replaceItemAt(destination, withItemAt: tempURL)
    }

    static func shellSingleQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    struct ProcessResult {
        let exitCode: Int32
        let stderr: String
    }

    static func runProcess(executable: String, arguments: [String]) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = pipe
        try process.run()
        let stderrData = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ProcessResult(
            exitCode: process.terminationStatus,
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }
}
