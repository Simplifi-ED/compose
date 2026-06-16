import Darwin
import Foundation

package struct SSHForwardPlan: Sendable, Equatable {
    package let guestSocketPath: String
    package let volumeFlag: String
    package let envFlag: String
}

package struct SSHEnvironment: Sendable {
    package let sshAuthSock: String?

    package init(sshAuthSock: String?) {
        self.sshAuthSock = sshAuthSock
    }
    package static let process = SSHEnvironment(
        sshAuthSock: ProcessInfo.processInfo.environment["SSH_AUTH_SOCK"]
    )
}

package enum SSHAgentForwarding {
    package static let guestSocketPath = "/run/ssh-auth.sock"
    /// container 1.0.0 BuildCommand has no `--ssh` (U0 spike).
    package static let buildSSHSupported = false

    package static func wantsForwarding(ssh: [String]?) -> Bool {
        guard let ssh, !ssh.isEmpty else { return false }
        return true
    }

    package static func parseEntries(_ entries: [String], field: String) throws {
        for entry in entries {
            let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed == "default" else {
                throw ComposeError.invalidField(
                    field,
                    reason: "only 'default' is supported (got '\(entry)')"
                )
            }
        }
    }

    package static func validateStartup(
        services: [String: ComposeService],
        activeServiceNames: Set<String>,
        environment: SSHEnvironment = .process,
        requireAgentReachability: Bool = true
    ) throws {
        for serviceName in activeServiceNames.sorted() {
            guard let service = services[serviceName], wantsForwarding(ssh: service.ssh) else { continue }
            try validateServiceSSH(
                serviceName: serviceName,
                ssh: service.ssh!,
                environment: environment,
                fieldPrefix: "services.\(serviceName).ssh",
                requireAgentReachability: requireAgentReachability
            )
        }
    }

    package static func validateServiceSSH(
        serviceName: String,
        ssh: [String],
        environment: SSHEnvironment = .process,
        fieldPrefix: String = "ssh",
        requireAgentReachability: Bool = true
    ) throws {
        try parseEntries(ssh, field: fieldPrefix)
        guard requireAgentReachability else { return }
        _ = try resolveForwardPlan(environment: environment, requireAgentReachability: true)
        _ = serviceName
    }

    package static func validateBuildSSH(
        serviceName: String,
        ssh: [String],
        environment: SSHEnvironment = .process
    ) throws {
        guard !ssh.isEmpty else { return }
        try parseEntries(ssh, field: "services.\(serviceName).build.ssh")
        guard buildSSHSupported else { return }
        _ = try resolveForwardPlan(environment: environment, requireAgentReachability: true)
    }

    package static func warnBuildSSHUnsupported(serviceName: String) {
        fputs(
            "warning: service '\(serviceName)': build.ssh is set but container build doesn't support --ssh; "
                + "private git access during image build won't work until the runtime adds build SSH forwarding.\n",
            stderr
        )
    }

    package static func resolveForwardPlan(
        environment: SSHEnvironment = .process,
        requireAgentReachability: Bool = true
    ) throws -> SSHForwardPlan {
        guard let sock = environment.sshAuthSock, !sock.isEmpty else {
            guard requireAgentReachability else {
                return SSHForwardPlan(
                    guestSocketPath: guestSocketPath,
                    volumeFlag: "$SSH_AUTH_SOCK:\(guestSocketPath):ro",
                    envFlag: "SSH_AUTH_SOCK=\(guestSocketPath)"
                )
            }
            throw ComposeError.invalidField(
                "ssh",
                reason: "SSH_AUTH_SOCK isn't set. Start ssh-agent, run ssh-add, and retry."
            )
        }

        let socketURL = URL(fileURLWithPath: sock).standardizedFileURL.resolvingSymlinksInPath()
        try validateSocketSecurity(url: socketURL)
        if requireAgentReachability {
            try validateSocketReachable(path: socketURL.path)
        }

        let volumeFlag = "\(socketURL.path):\(guestSocketPath):ro"
        let envFlag = "SSH_AUTH_SOCK=\(guestSocketPath)"
        return SSHForwardPlan(
            guestSocketPath: guestSocketPath,
            volumeFlag: volumeFlag,
            envFlag: envFlag
        )
    }

    package static func runFlags(
        service: ComposeService,
        environment: SSHEnvironment = .process,
        serviceName: String? = nil,
        logPhase: String = "run",
        requireAgentReachability: Bool = true
    ) throws -> [String] {
        guard wantsForwarding(ssh: service.ssh) else { return [] }
        let field = serviceName.map { "services.\($0).ssh" } ?? "ssh"
        try parseEntries(service.ssh!, field: field)
        let plan = try resolveForwardPlan(
            environment: environment,
            requireAgentReachability: requireAgentReachability
        )
        if let serviceName {
            logForward(serviceName: serviceName, phase: logPhase)
        }
        return ["-v", plan.volumeFlag, "-e", plan.envFlag]
    }

    package static func buildSSHArguments(
        ssh: [String],
        serviceName: String,
        environment: SSHEnvironment = .process
    ) throws -> [String] {
        guard !ssh.isEmpty else { return [] }
        try parseEntries(ssh, field: "services.\(serviceName).build.ssh")
        guard buildSSHSupported else {
            warnBuildSSHUnsupported(serviceName: serviceName)
            return []
        }
        _ = try resolveForwardPlan(environment: environment, requireAgentReachability: true)
        logForward(serviceName: serviceName, phase: "build")
        return ["--ssh", "default"]
    }

    package static func logForward(serviceName: String, phase: String) {
        OsLogTelemetry.enabled {
            OsLogTelemetry.orchestration.info(
                "event=ssh_forward service=\(serviceName, privacy: .public) phase=\(phase, privacy: .public)"
            )
        }
    }

    package static func validateSocketSecurity(url: URL) throws {
        let path = url.path
        var status = stat()
        guard stat(path, &status) == 0 else {
            throw ComposeError.invalidField(
                "ssh",
                reason: "SSH agent socket doesn't exist. Start ssh-agent, run ssh-add, and retry."
            )
        }
        guard (status.st_mode & S_IFMT) == S_IFSOCK else {
            throw ComposeError.invalidField(
                "ssh",
                reason: "SSH_AUTH_SOCK doesn't point to a socket. Start ssh-agent, run ssh-add, and retry."
            )
        }
        guard isPathAllowlisted(url) else {
            throw ComposeError.invalidField(
                "ssh",
                reason: "SSH agent socket path isn't in an allowed location for forwarding."
            )
        }
    }

    package static func validateSocketReachable(path: String) throws {
        guard SSHUnixSocket.canConnect(at: path) else {
            throw ComposeError.invalidField(
                "ssh",
                reason: "SSH agent socket isn't accepting connections. Restart ssh-agent, run ssh-add, and retry."
            )
        }
    }

    package static func isPathAllowlisted(_ url: URL) -> Bool {
        let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
        let path = resolved.path
        let prefixes = allowlistedPrefixes()
        if prefixes.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
            return true
        }
        return false
    }

    package static func allowlistedPrefixes() -> [String] {
        var prefixes = [
            "/private/tmp",
            "/tmp",
            "/var/folders",
            "/run"
        ]
        let temp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
        if !temp.isEmpty {
            prefixes.append(temp)
        }
        return prefixes
    }

    // compose-verify test helpers
    package static func copyUnixAddressPath(_ path: String, into addr: inout sockaddr_un) {
        SSHUnixSocket.copyAddressPath(path, into: &addr)
    }

    package static func unixSocketAddressLength(path: String) -> socklen_t {
        SSHUnixSocket.addressLength(path: path)
    }

    package static func prepareUnixSocketAddress(path: String) -> sockaddr_un {
        SSHUnixSocket.prepareAddress(path: path)
    }
}
