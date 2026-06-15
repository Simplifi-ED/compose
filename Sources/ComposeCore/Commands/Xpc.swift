import ArgumentParser
import Foundation

public struct Xpc: AsyncParsableCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        commandName: "xpc",
        abstract: "Local XPC automation service for trusted clients.",
        subcommands: [XpcServe.self, XpcInstall.self, XpcUninstall.self, XpcDoctor.self]
    )
}

public struct XpcServe: AsyncParsableCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        commandName: "serve",
        abstract: "Bootstrap the compose XPC Mach listener until interrupted (dev sessions)."
    )

    @Option(
        name: .long,
        help: "Path to the compose-xpc helper binary."
    )
    var binary: String?

    public func run() async throws {
        let helper = try resolvedComposeXPCBinary()
        defer {
            try? ComposeXPCLaunchAgent.uninstall()
        }
        try ComposeXPCLaunchAgent.startService(composeXPCBinary: helper)
        fputs(
            "compose XPC listening (Mach service: \(ComposeXPCConstants.machServiceName))\n",
            stderr
        )
        _ = try await SignalForwarding.runUntilCancelled(policy: .cancelOnly) {
            while true {
                try await Task.sleep(for: .seconds(3600))
            }
        }
    }

    private func resolvedComposeXPCBinary() throws -> URL {
        try XpcBinaryResolver.resolve(cliPath: binary)
    }
}

public struct XpcInstall: ParsableCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Install the user LaunchAgent for the compose XPC Mach service."
    )

    @Option(
        name: .long,
        help: "Path to the compose-xpc helper binary."
    )
    var binary: String?

    public func run() throws {
        let helper = try XpcBinaryResolver.resolve(cliPath: binary)
        try ComposeXPCLaunchAgent.install(composeXPCBinary: helper)
        print("Installed LaunchAgent \(ComposeXPCConstants.launchAgentLabel)")
    }
}

public struct XpcUninstall: ParsableCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "Remove the compose XPC LaunchAgent."
    )

    public func run() throws {
        try ComposeXPCLaunchAgent.uninstall()
        print("Removed LaunchAgent \(ComposeXPCConstants.launchAgentLabel)")
    }
}

public struct XpcDoctor: ParsableCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Check XPC listener install state and client allowlist readability."
    )

    public func run() throws {
        let installed = ComposeXPCLaunchAgent.isInstalled()
        print("launch_agent: \(installed ? "installed" : "not_installed")")
        print("mach_service: \(ComposeXPCConstants.machServiceName)")
        let clientsURL = ComposeXPCConstants.clientsConfigURL()
        if FileManager.default.fileExists(atPath: clientsURL.path) {
            let allowlist = ComposeXPCClientAuth.loadAllowlist()
            print("allowlist: \(clientsURL.path)")
            print("  team_ids: \(allowlist.teamIDs.count)")
            print("  clients: \(allowlist.clients.count)")
            if allowlist.teamIDs.isEmpty, allowlist.clients.isEmpty {
                if allowlist.allowAnySigned {
                    print("  warning: allowAnySigned is enabled — any signed client may connect")
                } else {
                    print(
                        "  warning: empty allowlist rejects all clients; set teamIDs, clients, or allowAnySigned"
                    )
                }
            }
        } else {
            print("allowlist: missing (\(clientsURL.path))")
            print("  warning: missing allowlist rejects all signed clients (create xpc-clients.json)")
        }
    }
}

enum XpcBinaryResolver {
    static func resolve(cliPath: String?) throws -> URL {
        if let cliPath {
            let url = URL(fileURLWithPath: cliPath)
            guard FileManager.default.isExecutableFile(atPath: url.path) else {
                throw ComposeXPCError.invalidRequest("compose-xpc binary is not executable: \(cliPath)")
            }
            return url
        }
        let sibling = URL(fileURLWithPath: CommandLine.arguments[0])
            .deletingLastPathComponent()
            .appendingPathComponent("compose-xpc")
        if FileManager.default.isExecutableFile(atPath: sibling.path) {
            return sibling
        }
        throw ComposeXPCError.invalidRequest(
            "compose-xpc binary not found beside compose; pass --binary."
        )
    }
}
