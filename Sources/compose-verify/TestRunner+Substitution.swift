import ComposeCore
import Foundation

extension TestRunner {
    mutating func runSubstitutionTests() throws {
        try runSubstitutionFixtureTests()
        try runSubstitutionUnitTests()
        try runSubstitutionAnchorTests()
        try runSubstitutionPrecedenceTests()
        try runSubstitutionPerFileEnvTests()
        try runSubstitutionVolumeEscapeTests()
    }

    mutating func runSubstitutionFixtureTests() throws {
        let fixtureURL = Self.fixtureURL("substitution-fixture/compose.yml")
        let parsed = try ComposeParser.parse(fileURL: fixtureURL, processEnvironment: [:])
        let web = parsed.services["web"]

        expect(web?.image == "docker.io/library/alpine:latest", "substitution required variable")
        expect(web?.ports == ["19091:80"], "substitution :- uses default when unset")
        expect(
            web?.environment == .map([
                "COLON_FALLBACK": "fallback",
                "DASH_DEFAULT": "default-value",
                "DASH_EMPTY_OK": "",
                "ESCAPED_DOLLAR": "$VAR",
                "ESCAPED_PRICE": "price is $100"
            ]),
            "substitution defaults and dollar escapes"
        )
    }

    mutating func runSubstitutionUnitTests() throws {
        let colonUnset = try ComposeSubstitution.substitute(
            "value: ${MISSING:-fallback}",
            variables: [:],
            composePath: "/tmp/compose.yml"
        )
        expect(colonUnset == "value: fallback", ":- default when unset")

        let colonEmpty = try ComposeSubstitution.substitute(
            "value: ${EMPTY:-fallback}",
            variables: ["EMPTY": ""],
            composePath: "/tmp/compose.yml"
        )
        expect(colonEmpty == "value: fallback", ":- default when empty")

        let dashUnset = try ComposeSubstitution.substitute(
            "value: ${MISSING-default}",
            variables: [:],
            composePath: "/tmp/compose.yml"
        )
        expect(dashUnset == "value: default", "- default when unset")

        let dashEmpty = try ComposeSubstitution.substitute(
            "value: ${EMPTY-ignored}",
            variables: ["EMPTY": ""],
            composePath: "/tmp/compose.yml"
        )
        expect(dashEmpty == "value: ", "- preserves empty string when set")

        let escaped = try ComposeSubstitution.substitute(
            "cmd: $$VAR and $$",
            variables: [:],
            composePath: "/tmp/compose.yml"
        )
        expect(escaped == "cmd: $VAR and $", "double-dollar escape")

        let commentSkipped = try ComposeSubstitution.substitute(
            "# legacy: ${OLD}\nimage: ok",
            variables: [:],
            composePath: "/tmp/compose.yml"
        )
        expect(commentSkipped == "# legacy: ${OLD}\nimage: ok", "substitution skips comment lines")

        let indirect = try ComposeSubstitution.substitute(
            "image: ${A}",
            variables: ["A": "${B}", "B": "hello"],
            composePath: "/tmp/compose.yml"
        )
        expect(indirect == "image: ${B}", "single-pass substitution without re-expansion")

        let literalColon = try ComposeSubstitution.substitute(
            "url: ${jdbc:postgresql://db}",
            variables: [:],
            composePath: "/tmp/compose.yml"
        )
        expect(
            literalColon == "url: ${jdbc:postgresql://db}",
            "non-compose braced colons are preserved literally"
        )

        let emptyDefault = try ComposeSubstitution.substitute(
            "value: ${MISSING:-}",
            variables: [:],
            composePath: "/tmp/compose.yml"
        )
        expect(emptyDefault == "value: ", ":- allows empty default")

        let requiredEmpty = try ComposeSubstitution.substitute(
            "value: ${EMPTY}",
            variables: ["EMPTY": ""],
            composePath: "/tmp/compose.yml"
        )
        expect(requiredEmpty == "value: ", "required variable accepts empty string when set")

        let noNewline = try ComposeSubstitution.substitute(
            "image: ok",
            variables: [:],
            composePath: "/tmp/compose.yml"
        )
        expect(noNewline == "image: ok", "content without trailing newline unchanged")
    }

    mutating func runSubstitutionAnchorTests() throws {
        let anchorURL = Self.fixtureURL("substitution-fixture/anchor-compose.yml")
        let anchored = try ComposeParser.parse(fileURL: anchorURL, processEnvironment: [:])
        expect(anchored.services.count == 2, "anchor fixture service count")
        expect(anchored.services["web"]?.image == "docker.io/library/alpine:latest", "anchor scalar alias web")
        expect(anchored.services["api"]?.image == "docker.io/library/alpine:latest", "anchor scalar alias api")

        let baseURL = Self.fixtureURL("substitution-fixture/anchor-merge-base.yml")
        let overrideURL = Self.fixtureURL("substitution-fixture/anchor-merge-override.yml")
        let merged = try ComposeParser.parse(fileURLs: [baseURL, overrideURL], processEnvironment: [:])
        expect(merged.services.count == 1, "anchor merge single web service")
        let web = merged.services["web"]
        expect(web?.image == "docker.io/library/alpine:latest", "anchor merge override image")
        expect(web?.command == .string("sleep 300"), "anchor merge keeps base command")
    }

    mutating func runSubstitutionPrecedenceTests() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("compose-verify-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let composePath = tempDir.appendingPathComponent("compose.yml")
        try "IMAGE=from-dotenv".write(
            to: tempDir.appendingPathComponent(".env"),
            atomically: true,
            encoding: .utf8
        )
        try """
        services:
          web:
            image: ${IMAGE}
        """.write(to: composePath, atomically: true, encoding: .utf8)

        let variables = try ComposeSubstitution.resolveVariables(
            beside: composePath,
            processEnvironment: ["IMAGE": "from-shell"]
        )
        expect(variables["IMAGE"] == "from-shell", "process environment overrides .env")

        let hydrated = try ComposeSubstitution.substitute(
            "image: ${IMAGE}",
            variables: variables,
            composePath: composePath.path
        )
        expect(hydrated == "image: from-shell", "substitution uses process environment value")
    }

    mutating func runSubstitutionPerFileEnvTests() throws {
        let fixtureRoot = Self.fixtureURL("substitution-fixture/compose.yml").deletingLastPathComponent()
        let baseURL = fixtureRoot.appendingPathComponent("multi-base/compose.yml")
        let overrideURL = fixtureRoot.appendingPathComponent("multi-override/compose.yml")

        let baseOnly = try ComposeParser.parse(fileURL: baseURL, processEnvironment: [:])
        expect(
            baseOnly.services["web"]?.image == "docker.io/library/alpine:3.18",
            "per-file .env beside base compose file"
        )

        let merged = try ComposeParser.parse(fileURLs: [baseURL, overrideURL], processEnvironment: [:])
        expect(
            merged.services["web"]?.image == "docker.io/library/alpine:latest",
            "per-file .env beside override compose file wins on merge"
        )
        expect(merged.services["web"]?.command == .string("sleep 300"), "per-file merge keeps base command")
    }

    mutating func runSubstitutionVolumeEscapeTests() throws {
        let fixturesDirectory = Self.fixtureURL("substitution-fixture/compose.yml").deletingLastPathComponent()
        expectComposeError(
            "relative volume escapes compose directory",
            matching: { if case .invalidField("volumes", _) = $0 { true } else { false } },
            body: {
                _ = try ServicePlanner.volumeFlag(
                    for: "../../outside:/mnt/outside",
                    relativeTo: fixturesDirectory
                )
            }
        )

        let hostPath = try ComposeSubstitution.substitute(
            "${HOST_PATH}",
            variables: ["HOST_PATH": "/tmp"],
            composePath: "/tmp/compose.yml"
        )
        let absoluteVolume = try ServicePlanner.volumeFlag(
            for: "\(hostPath):/mnt/data",
            relativeTo: fixturesDirectory
        )
        expect(absoluteVolume == "/tmp:/mnt/data", "substitution-expanded absolute volume allowed")
    }
}
