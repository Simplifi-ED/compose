import ComposeCore
import Foundation

extension TestRunner {
    mutating func runDotEnvTests() throws {
        try runDotEnvFixtureTests()
        try runDotEnvUnitTests()
        try runDotEnvUnresolvedTests()
    }

    mutating func runDotEnvFixtureTests() throws {
        let fixtureURL = Self.fixtureURL("env-fixture/env-compose.yml")
        let parsed = try ComposeParser.parse(fileURL: fixtureURL)
        let web = parsed.services["web"]

        expect(web?.image == "docker.io/library/alpine:latest", "env fixture image substitution")
        expect(web?.ports == ["19090:80"], "env fixture port substitution")
        expect(web?.environment == .map(["FOO": "from-dotenv"]), "env fixture environment substitution")

        let minimal = try ComposeParser.parse(fileURL: Self.fixtureURL("minimal-compose.yml"))
        expect(minimal.services["web"]?.image == "docker.io/library/alpine:latest", "missing .env is no-op")
    }

    mutating func runDotEnvUnitTests() throws {
        let parsed = DotEnv.parse(
            """
            # comment line
            bad-key=value
            NOEQUALS
            IMAGE=alpine:latest
            DUPLICATE=first
            DUPLICATE=second
            """
        )
        expect(parsed["IMAGE"] == "alpine:latest", "dotenv parses KEY=VALUE")
        expect(parsed["DUPLICATE"] == "second", "dotenv duplicate keys last wins")
        expect(parsed["bad-key"] == nil, "dotenv skips invalid keys")
        expect(parsed["NOEQUALS"] == nil, "dotenv skips lines without equals")

        let substituted = try DotEnv.substitute(
            "image: ${IMAGE} ports: ${IMAGE}",
            variables: ["IMAGE": "alpine:latest"],
            composePath: "/tmp/compose.yml"
        )
        expect(substituted == "image: alpine:latest ports: alpine:latest", "dotenv multiple placeholders")

        let indirect = try DotEnv.substitute(
            "image: ${A}",
            variables: ["A": "${B}", "B": "hello"],
            composePath: "/tmp/compose.yml"
        )
        expect(indirect == "image: ${B}", "indirect env value substitutes one level without false-positive error")
    }

    mutating func runDotEnvUnresolvedTests() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("compose-verify-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let composePath = tempDir.appendingPathComponent("compose.yml")
        try """
        services:
          web:
            image: ${MISSING_VAR}
        """.write(to: composePath, atomically: true, encoding: .utf8)

        expectComposeError(
            "unresolved placeholder",
            matching: { if case .unresolvedVariable(let name, _) = $0 { name == "MISSING_VAR" } else { false } },
            body: { _ = try ComposeParser.parse(fileURL: composePath) }
        )
    }
}
