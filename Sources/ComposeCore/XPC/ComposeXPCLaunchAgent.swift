import Foundation

package enum ComposeXPCLaunchAgent {
    package static func install(composeXPCBinary: URL) throws {
        try startService(composeXPCBinary: composeXPCBinary)
    }

    package static func startService(composeXPCBinary: URL) throws {
        try writePlist(composeXPCBinary: composeXPCBinary)
        try bootstrapIfNeeded()
    }

    package static func uninstall() throws {
        try bootout()
        try removePlistIfPresent()
    }

    package static func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: plistURL().path)
    }

    package static func bootout() throws {
        let uid = getuid()
        let status = runLaunchctl(["bootout", "gui/\(uid)/\(ComposeXPCConstants.launchAgentLabel)"])
        guard status == 0 || status == 3 else {
            throw ComposeXPCError.nsError(
                code: .operationFailed,
                message: "launchctl bootout failed (exit \(status))."
            )
        }
    }

    private static func plistURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent(ComposeXPCConstants.launchAgentPlistName)
    }

    private static func writePlist(composeXPCBinary: URL) throws {
        let agentsDirectory = plistURL().deletingLastPathComponent()
        try FileManager.default.createDirectory(at: agentsDirectory, withIntermediateDirectories: true)
        let plist = launchAgentPlist(binary: composeXPCBinary)
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: plistURL(), options: .atomic)
    }

  /// Single source for `Resources/LaunchAgents/com.simplifi-ed.container-compose.xpc.plist` (reference copy).
    package static func launchAgentPlist(binary: URL) -> [String: Any] {
        [
            "Label": ComposeXPCConstants.launchAgentLabel,
            "ProgramArguments": [binary.path, "--mach"],
            "RunAtLoad": true,
            "KeepAlive": true,
            "MachServices": [
                ComposeXPCConstants.machServiceName: true
            ]
        ]
    }

    private static func removePlistIfPresent() throws {
        let url = plistURL()
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private static func bootstrapIfNeeded() throws {
        let uid = getuid()
        let status = runLaunchctl(["bootstrap", "gui/\(uid)", plistURL().path])
        guard status == 0 || status == 37 else {
            throw ComposeXPCError.nsError(
                code: .operationFailed,
                message: "launchctl bootstrap failed (exit \(status))."
            )
        }
    }

    @discardableResult
    private static func runLaunchctl(_ arguments: [String]) -> Int32 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = arguments
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus
        } catch {
            return -1
        }
    }
}
