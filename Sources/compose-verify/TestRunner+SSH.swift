import ComposeCore
import ContainerCommands
import Foundation

#if canImport(Darwin)
import Darwin
#endif

extension TestRunner {
    mutating func runSSHTests() throws {
#if canImport(Darwin)
        try runSSHForwardPlanTests()
        try runSSHValidationErrorTests()
        try runSSHMultiServiceTests()
        try runSSHBuildMergeTests()
        try runSSHBuildWarningTests()
        try runSSHConfigRoundTripTests()
        try runSSHAllowlistTests()
        try runSSHDryRunTests()
#else
        _ = self
#endif
    }

#if canImport(Darwin)
    private mutating func runSSHForwardPlanTests() throws {
        try SSHTestSocket.withListeningSocket { path, environment in
            let service = ComposeService(
                image: "docker.io/library/alpine:3.20",
                command: nil,
                ports: [],
                environment: nil,
                containerName: nil,
                ssh: ["default"]
            )
            let flags = try SSHAgentForwarding.runFlags(
                service: service,
                environment: environment,
                serviceName: "web"
            )
            expect(flags.contains("-v"), "ssh run flags include volume")
            expect(flags.contains("-e"), "ssh run flags include env")
            let volume = runArgumentValue(flags, flag: "-v")
            expect(volume?.contains(":/run/ssh-auth.sock:ro") == true, "ssh volume uses stable guest path")
            expect(volume?.hasPrefix(path) == true, "ssh volume source is host socket")
            let env = runArgumentValue(flags, flag: "-e")
            expect(env == "SSH_AUTH_SOCK=/run/ssh-auth.sock", "ssh env sets guest socket path")
        }
    }

    private mutating func runSSHValidationErrorTests() throws {
        try runSSHValidationParseTests()
        try runSSHValidationDeadSocketTests()
    }

    private mutating func runSSHValidationParseTests() throws {
        expectComposeError("ssh invalid entry") { error in
            if case .invalidField(let field, let reason) = error {
                return field == "ssh" && reason.contains("only 'default'")
            }
            return false
        } body: {
            try SSHAgentForwarding.parseEntries(["foo"], field: "ssh")
        }

        expectComposeError("missing SSH_AUTH_SOCK") { error in
            if case .invalidField(_, let reason) = error {
                return reason.contains("SSH_AUTH_SOCK")
            }
            return false
        } body: {
            _ = try SSHAgentForwarding.resolveForwardPlan(
                environment: SSHEnvironment(sshAuthSock: nil),
                requireAgentReachability: true
            )
        }

        let stalePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("compose-verify-stale-\(UUID().uuidString)").path
        FileManager.default.createFile(atPath: stalePath, contents: Data())
        defer { try? FileManager.default.removeItem(atPath: stalePath) }
        expectComposeError("stale ssh socket") { error in
            if case .invalidField(_, let reason) = error {
                return reason.contains("accepting connections")
                    || reason.contains("doesn't point to a socket")
            }
            return false
        } body: {
            _ = try SSHAgentForwarding.resolveForwardPlan(
                environment: SSHEnvironment(sshAuthSock: stalePath),
                requireAgentReachability: true
            )
        }
    }

    private mutating func runSSHValidationDeadSocketTests() throws {
        let deadSocketPath = "/tmp/cv-dead-\(UUID().uuidString.prefix(8))"
        unlink(deadSocketPath)
        let deadFD = socket(AF_UNIX, SOCK_STREAM, 0)
        if deadFD >= 0 {
            var deadAddr = sockaddr_un()
            deadAddr.sun_family = sa_family_t(AF_UNIX)
            SSHAgentForwarding.copyUnixAddressPath(deadSocketPath, into: &deadAddr)
            let deadLen = SSHAgentForwarding.unixSocketAddressLength(path: deadSocketPath)
            deadAddr.sun_len = UInt8(truncatingIfNeeded: deadLen)
            let bound = withUnsafePointer(to: &deadAddr) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    bind(deadFD, sockaddrPointer, deadLen) == 0
                }
            }
            if bound {
                close(deadFD)
                defer { unlink(deadSocketPath) }
                expectComposeError("dead ssh socket") { error in
                    if case .invalidField(_, let reason) = error {
                        return reason.contains("accepting connections")
                    }
                    return false
                } body: {
                    _ = try SSHAgentForwarding.resolveForwardPlan(
                        environment: SSHEnvironment(sshAuthSock: deadSocketPath),
                        requireAgentReachability: true
                    )
                }
            } else {
                close(deadFD)
            }
        }
    }

    private mutating func runSSHMultiServiceTests() throws {
        try SSHTestSocket.withListeningSocket { _, environment in
            let web = ComposeService(
                image: "docker.io/library/alpine:3.20",
                command: nil,
                ports: [],
                environment: nil,
                containerName: nil,
                ssh: ["default"]
            )
            let api = ComposeService(
                image: "docker.io/library/alpine:3.20",
                command: nil,
                ports: [],
                environment: nil,
                containerName: nil,
                ssh: ["default"]
            )
            let webFlags = try SSHAgentForwarding.runFlags(
                service: web,
                environment: environment,
                serviceName: "web"
            )
            let apiFlags = try SSHAgentForwarding.runFlags(
                service: api,
                environment: environment,
                serviceName: "api"
            )
            expect(webFlags.contains { $0.contains("/run/ssh-auth.sock:ro") }, "web ssh mount")
            expect(apiFlags.contains { $0.contains("/run/ssh-auth.sock:ro") }, "api ssh mount")
            expect(webFlags.filter { $0 == "-v" }.count == 1, "web has one ssh volume flag")
            expect(apiFlags.filter { $0 == "-v" }.count == 1, "api has one ssh volume flag")
        }
    }

    private mutating func runSSHBuildMergeTests() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("compose-verify-ssh-merge-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let baseURL = tempDir.appendingPathComponent("compose.yml")
        let overrideURL = tempDir.appendingPathComponent("compose.override.yml")
        try """
        services:
          web:
            build:
              context: .
              ssh:
                - default
        """.write(to: baseURL, atomically: true, encoding: .utf8)
        try """
        services:
          web:
            build:
              context: .
              dockerfile: Dockerfile.dev
        """.write(to: overrideURL, atomically: true, encoding: .utf8)

        let merged = try ComposeParser.parse(fileURLs: [baseURL, overrideURL])
        let build = merged.services["web"]?.build
        expect(build?.ssh == ["default"], "build.ssh preserved when override changes dockerfile")
        expect(build?.dockerfile == "Dockerfile.dev", "build.dockerfile overridden")
    }

    private mutating func runSSHBuildWarningTests() throws {
        let (_, captured) = try StandardStreamCapture.captureStandardError {
            _ = try SSHAgentForwarding.buildSSHArguments(
                ssh: ["default"],
                serviceName: "web",
                environment: SSHEnvironment(sshAuthSock: nil)
            )
        }
        expect(captured.contains("doesn't support --ssh"), "build.ssh emits unsupported warning")
        try SSHAgentForwarding.validateBuildSSH(
            serviceName: "web",
            ssh: ["default"],
            environment: SSHEnvironment(sshAuthSock: nil)
        )
    }

    private mutating func runSSHDryRunTests() throws {
        let service = ComposeService(
            image: "docker.io/library/alpine:3.20",
            command: nil,
            ports: [],
            environment: nil,
            containerName: nil,
            ssh: ["default"]
        )
        try SSHAgentForwarding.validateServiceSSH(
            serviceName: "web",
            ssh: ["default"],
            environment: SSHEnvironment(sshAuthSock: nil),
            requireAgentReachability: false
        )
        let flags = try SSHAgentForwarding.runFlags(
            service: service,
            environment: SSHEnvironment(sshAuthSock: nil),
            serviceName: "web",
            requireAgentReachability: false
        )
        let volume = runArgumentValue(flags, flag: "-v")
        expect(volume?.contains("$SSH_AUTH_SOCK:/run/ssh-auth.sock:ro") == true, "dry-run ssh uses env placeholder")
    }

    private mutating func runSSHConfigRoundTripTests() throws {
        let service = ComposeService(
            image: "docker.io/library/alpine:3.20",
            command: nil,
            ports: [],
            environment: nil,
            containerName: nil,
            ssh: ["default"]
        )
        let composeFile = ComposeFile(name: "ssh-demo", services: ["web": service])
        let yaml = try ComposeSerializer.yamlString(from: composeFile)
        expect(yaml.contains("ssh:"), "config yaml includes ssh key")
        expect(yaml.contains("default"), "config yaml includes default forwarding")
        expect(!yaml.contains("/run/ssh-auth.sock"), "config yaml omits resolved guest socket path")
        expect(!yaml.contains("SSH_AUTH_SOCK"), "config yaml omits runtime env")
    }

    private mutating func runSSHAllowlistTests() throws {
        try SSHTestSocket.withListeningSocket { path, environment in
            let url = URL(fileURLWithPath: path)
            expect(SSHAgentForwarding.isPathAllowlisted(url), "temp dir socket is allowlisted")
            _ = try SSHAgentForwarding.resolveForwardPlan(environment: environment, requireAgentReachability: true)
        }
        let blocked = URL(fileURLWithPath: "/etc/passwd")
        expect(!SSHAgentForwarding.isPathAllowlisted(blocked), "/etc/passwd outside ssh allowlist")

        let outsidePath = "/var/tmp/cv-\(UUID().uuidString.prefix(8))"
        unlink(outsidePath)
        let outsideFD = socket(AF_UNIX, SOCK_STREAM, 0)
        if outsideFD >= 0 {
            defer { close(outsideFD); unlink(outsidePath) }
            var outsideAddr = SSHAgentForwarding.prepareUnixSocketAddress(path: outsidePath)
            let outsideLen = SSHAgentForwarding.unixSocketAddressLength(path: outsidePath)
            let outsideBound = withUnsafePointer(to: &outsideAddr) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    bind(outsideFD, sockaddrPointer, outsideLen) == 0
                }
            }
            guard outsideBound, listen(outsideFD, 128) == 0 else { return }
            expectComposeError("ssh socket outside allowlist") { error in
                if case .invalidField(_, let reason) = error {
                    return reason.contains("allowed location")
                }
                return false
            } body: {
                _ = try SSHAgentForwarding.resolveForwardPlan(
                    environment: SSHEnvironment(sshAuthSock: outsidePath),
                    requireAgentReachability: true
                )
            }
        }
    }
#endif
}

#if canImport(Darwin)
private enum SSHTestSocket {
    static func withListeningSocket(
        _ body: (String, SSHEnvironment) throws -> Void
    ) throws {
        let path = "/tmp/cv-\(UUID().uuidString.prefix(8))"
        unlink(path)
        let listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFD >= 0 else {
            throw ComposeError.invalidField("ssh", reason: "test socket setup failed")
        }
        defer {
            close(listenFD)
            unlink(path)
        }

        var addr = SSHAgentForwarding.prepareUnixSocketAddress(path: path)
        let bindLength = SSHAgentForwarding.unixSocketAddressLength(path: path)
        let bindResult = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(listenFD, sockaddrPointer, bindLength)
            }
        }
        guard bindResult == 0 else {
            throw ComposeError.invalidField("ssh", reason: "test socket bind failed")
        }
        guard listen(listenFD, 128) == 0 else {
            throw ComposeError.invalidField("ssh", reason: "test socket listen failed")
        }

        try body(path, SSHEnvironment(sshAuthSock: path))
    }
}
#endif
