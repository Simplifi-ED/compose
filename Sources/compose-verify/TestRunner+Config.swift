import ComposeCore
import Foundation

extension TestRunner {
    mutating func runConfigTests() throws {
        try runConfigMergeTests()
        try runConfigSubstitutionErrorTests()
        try runConfigProfileTests()
        try runConfigScaleTests()
        try runConfigMinimalFixtureTests()
        try runConfigUpParityTests()
        try runConfigIncludeTests()
        try runConfigQuietOutputTests()
        try runConfigHealthcheckExportTests()
    }

    private mutating func runConfigMergeTests() throws {
        let mergeDir = Self.fixtureURL("merge/base.yml").deletingLastPathComponent()
        let fileURLs = [
            mergeDir.appendingPathComponent("base.yml"),
            mergeDir.appendingPathComponent("override.yml")
        ]
        let resolved = try ComposeConfigResolver.resolve(
            fileURLs: fileURLs,
            activeProfiles: [],
            scaleOverrides: [:]
        )
        expect(resolved.name == "override-project", "config merge smoke name from last file")
        expect(resolved.services["cache"] != nil, "config merge smoke includes merged services")

        let yaml = try ComposeSerializer.yamlString(from: resolved)
        expect(yaml.contains("name: override-project\n"), "config yaml includes merged project name")
        expect(yaml.contains("services:"), "config yaml includes services block")
        expect(yaml.contains("  cache:\n"), "config yaml lists services alphabetically")
        let cacheOffset = yaml.range(of: "  cache:\n")?.lowerBound
        let debugOffset = yaml.range(of: "  debug:\n")?.lowerBound
        let webOffset = yaml.range(of: "  web:\n")?.lowerBound
        if let cacheOffset, let debugOffset, let webOffset {
            expect(cacheOffset < debugOffset, "config yaml orders cache before debug")
            expect(debugOffset < webOffset, "config yaml orders debug before web")
        } else {
            expect(false, "config yaml missing expected service keys")
        }
    }

    private mutating func runConfigSubstitutionErrorTests() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("compose-verify-config-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let composePath = tempDir.appendingPathComponent("compose.yml")
        try """
        services:
          web:
            image: ${MISSING_VAR}
        """.write(to: composePath, atomically: true, encoding: .utf8)

        expectComposeError(
            "config unresolved variable",
            matching: { if case .unresolvedVariable(let name, _) = $0 { name == "MISSING_VAR" } else { false } },
            body: {
                _ = try ComposeConfigResolver.resolve(
                    fileURLs: [composePath],
                    activeProfiles: [],
                    scaleOverrides: [:],
                    processEnvironment: [:]
                )
            }
        )
    }

    private mutating func runConfigProfileTests() throws {
        let fixtureURL = Self.fixtureURL("profiles-compose.yml")
        let resolved = try ComposeConfigResolver.resolve(
            fileURLs: [fixtureURL],
            activeProfiles: ["debug"],
            scaleOverrides: [:]
        )
        expect(resolved.services["web"] != nil, "config profile debug keeps unprofiled web")
        expect(resolved.services["db"] != nil, "config profile debug keeps unprofiled db")
        expect(resolved.services["debugger"] != nil, "config profile debug includes debugger")
        expect(resolved.services["metrics"] == nil, "config profile debug excludes metrics")

        let yaml = try ComposeSerializer.yamlString(from: resolved)
        expect(yaml.contains("  debugger:\n"), "config profile yaml includes debugger")
        expect(!yaml.contains("  metrics:\n"), "config profile yaml excludes metrics")
    }

    private mutating func runConfigScaleTests() throws {
        let fixtureURL = Self.fixtureURL("scale-compose.yml")
        let resolved = try ComposeConfigResolver.resolve(
            fileURLs: [fixtureURL],
            activeProfiles: [],
            scaleOverrides: ["web": 3]
        )
        expect(resolved.services["web"]?.deploy?.replicas == 3, "config scale override updates deploy.replicas")

        let yaml = try ComposeSerializer.yamlString(from: resolved)
        expect(yaml.contains("    replicas: 3\n"), "config scale yaml shows overridden replicas")
    }

    private mutating func runConfigUpParityTests() throws {
        let fixtureURL = Self.fixtureURL("scale-ports-compose.yml")

        expectComposeError(
            "config rejects static host port with multiple replicas",
            matching: { if case .staticPortBlocksScaling = $0 { true } else { false } },
            body: {
                _ = try ComposeConfigResolver.resolve(
                    fileURLs: [fixtureURL],
                    activeProfiles: [],
                    scaleOverrides: [:]
                )
            }
        )

        let resolved = try ComposeConfigResolver.resolve(
            fileURLs: [fixtureURL],
            activeProfiles: [],
            scaleOverrides: ["web": 1]
        )
        expect(resolved.services["web"]?.deploy?.replicas == 1, "config scale down clears multi-replica port conflict")
    }

    private mutating func runConfigIncludeTests() throws {
        let fixtureURL = Self.fixtureURL("include-fixture/root.yml")
        let resolved = try ComposeConfigResolver.resolve(
            fileURLs: [fixtureURL],
            activeProfiles: [],
            scaleOverrides: [:]
        )
        expect(resolved.services["app"] != nil, "config include expands root service")
        expect(resolved.services["web"] != nil, "config include expands included web service")
        expect(resolved.services["db"] != nil, "config include expands included db service")

        let yaml = try ComposeSerializer.yamlString(from: resolved)
        expect(!yaml.contains("project_directory"), "config yaml omits project_directory metadata")
    }

    private mutating func runConfigQuietOutputTests() throws {
        let fixtureURL = Self.fixtureURL("minimal-compose.yml")
        let quietOutput = try ComposeConfigResolver.resolveOutput(
            fileURLs: [fixtureURL],
            activeProfiles: [],
            scaleOverrides: [:],
            quiet: true
        )
        expect(quietOutput == nil, "config quiet returns no yaml")

        let yaml = try ComposeConfigResolver.resolveOutput(
            fileURLs: [fixtureURL],
            activeProfiles: [],
            scaleOverrides: [:],
            quiet: false
        )
        expect(yaml?.contains("services:") == true, "config non-quiet returns yaml")
    }

    private mutating func runConfigHealthcheckExportTests() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("compose-verify-config-hc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let testOnlyPath = tempDir.appendingPathComponent("compose.yml")
        try """
        services:
          web:
            image: docker.io/library/alpine:latest
            healthcheck:
              test: ["CMD", "true"]
        """.write(to: testOnlyPath, atomically: true, encoding: .utf8)

        let testOnlyYAML = try ComposeSerializer.yamlString(
            from: ComposeConfigResolver.resolve(
                fileURLs: [testOnlyPath],
                activeProfiles: [],
                scaleOverrides: [:]
            )
        )
        expect(testOnlyYAML.contains("test:"), "healthcheck export includes test")
        expect(!testOnlyYAML.contains("interval:"), "healthcheck export omits default interval")
        expect(!testOnlyYAML.contains("timeout:"), "healthcheck export omits default timeout")
        expect(!testOnlyYAML.contains("retries:"), "healthcheck export omits default retries")
        expect(!testOnlyYAML.contains("start_period:"), "healthcheck export omits default start_period")

        let fullFixture = Self.fixtureURL("healthcheck-compose.yml")
        let fullYAML = try ComposeSerializer.yamlString(
            from: ComposeConfigResolver.resolve(
                fileURLs: [fullFixture],
                activeProfiles: [],
                scaleOverrides: [:]
            )
        )
        expect(fullYAML.contains("interval: 1s"), "healthcheck export keeps explicit interval")
        expect(fullYAML.contains("retries: 2"), "healthcheck export keeps explicit retries")
    }

    private mutating func runConfigMinimalFixtureTests() throws {
        let fixtureURL = Self.fixtureURL("minimal-compose.yml")
        let resolved = try ComposeConfigResolver.resolve(
            fileURLs: [fixtureURL],
            activeProfiles: [],
            scaleOverrides: [:]
        )
        expect(resolved.services.count == 1, "config resolves minimal fixture")
        let yaml = try ComposeSerializer.yamlString(from: resolved)
        expect(yaml.contains("  web:\n"), "config minimal yaml includes web service")
    }
}
