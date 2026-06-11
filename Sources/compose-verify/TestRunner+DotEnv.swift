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
        let parsed = try ComposeParser.parse(fileURL: fixtureURL, processEnvironment: [:])
        let web = parsed.services["web"]

        expect(web?.image == "docker.io/library/alpine:latest", "env fixture image substitution")
        expect(web?.ports == ["19090:80"], "env fixture port substitution")
        expect(
            web?.environment == .map(["FOO": "from-dotenv", "FLAG": "true"]),
            "env fixture quoted environment substitution preserves string values"
        )

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

        let spacedKey = DotEnv.parse("FOO =bar\n")
        expect(spacedKey["FOO"] == "bar", "dotenv trims whitespace around key")

        let substituted = try ComposeSubstitution.substitute(
            "image: ${IMAGE} ports: ${IMAGE}",
            variables: ["IMAGE": "alpine:latest"],
            composePath: "/tmp/compose.yml"
        )
        expect(substituted == "image: alpine:latest ports: alpine:latest", "dotenv multiple placeholders")
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
            body: { _ = try ComposeParser.parse(fileURL: composePath, processEnvironment: [:]) }
        )
    }
}
