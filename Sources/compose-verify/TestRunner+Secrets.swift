import ComposeCore
import ContainerCommands
import Foundation

extension TestRunner {
    mutating func runSecretsTests() throws {
        try runSecretsSpikeTests()
        try runSecretsParseTests()
        try runSecretsValidationTests()
        try runSecretsPlannerTests()
        try runSecretsConfigExportTests()
        try runSecretsMergeTests()
    }

    mutating func runSecretsSpikeTests() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("compose-verify-secret-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let secretFile = tempDir.appendingPathComponent("secret.txt")
        try "secret-bytes".write(to: secretFile, atomically: true, encoding: .utf8)

        let args = [
            "-v",
            ComposeFileMountResolver.readOnlyVolumeFlag(
                hostPath: secretFile.path,
                containerPath: "/run/secrets/x"
            ),
            "docker.io/library/alpine:3.20"
        ]
        _ = try Application.ContainerRun.parse(args)
    }

    mutating func runSecretsParseTests() throws {
        let fixture = try ComposeParser.parse(fileURL: Self.fixtureURL("secrets-compose.yml"))
        expect(fixture.secrets["db_password"]?.file == "./secrets/db_password.txt", "secrets root decode")
        expect(fixture.services["app"]?.secrets.map(\.source) == ["db_password"], "service secret ref decode")

        let combined = try ComposeParser.parse(fileURL: Self.fixtureURL("configs-secrets-compose.yml"))
        expect(combined.configs["app_config"]?.file == "./secrets/app_config.txt", "configs root decode")
        expect(combined.services["app"]?.configs.map(\.source) == ["app_config"], "service config ref decode")
    }

    mutating func runSecretsValidationTests() throws {
        expectComposeError(
            "missing secret file",
            matching: {
                if case .resourceFileNotFound(let path, .secret) = $0 {
                    return path == "./secrets/missing.txt"
                }
                return false
            },
            body: {
                _ = try ComposeConfigResolver.resolve(
                    fileURLs: [Self.fixtureURL("missing-secret-compose.yml")],
                    activeProfiles: [],
                    scaleOverrides: [:]
                )
            }
        )

        expectComposeError(
            "undefined secret",
            matching: {
                if case .undefinedResource(name: "missing_secret", kind: .secret) = $0 { true } else { false }
            },
            body: {
                _ = try ServicePlanner.startupLayers(
                    for: try ComposeParser.parse(fileURL: Self.fixtureURL("undefined-secret-compose.yml")),
                    projectName: "demo",
                    composeDirectory: Self.fixtureURL("undefined-secret-compose.yml").deletingLastPathComponent()
                )
            }
        )
    }

    mutating func runSecretsPlannerTests() throws {
        let fixturesDirectory = Self.fixtureURL("secrets-compose.yml").deletingLastPathComponent()
        let composeFile = try ComposeParser.parse(fileURL: Self.fixtureURL("secrets-compose.yml"))
        let layers = try ServicePlanner.startupLayers(
            for: composeFile,
            projectName: "demo",
            composeDirectory: fixturesDirectory
        )
        guard let plan = layers.first?.first else {
            expect(false, "secrets planner produced a plan")
            return
        }
        expect(plan.fileMounts.count == 1, "secrets planner file mount count")
        expect(plan.fileMounts[0].containerTarget == "/run/secrets/db_password", "secrets planner target path")
        expect(plan.image == "docker.io/library/alpine:3.20", "secrets planner image")

        let stagedArgs = try ComposeFileStaging.preparedRunArguments(for: plan)
        expect(stagedArgs.contains(where: { $0.hasSuffix(":ro") }), "secrets staged mount uses :ro")
        _ = try Application.ContainerRun.parse(stagedArgs)
    }

    mutating func runSecretsConfigExportTests() throws {
        let yaml = try ComposeConfigResolver.resolveOutput(
            fileURLs: [Self.fixtureURL("configs-secrets-compose.yml")],
            activeProfiles: [],
            scaleOverrides: [:]
        )
        guard let yaml else {
            expect(false, "config export returned yaml")
            return
        }
        expect(yaml.contains("secrets:"), "config export includes secrets block")
        expect(yaml.contains("configs:"), "config export includes configs block")
        expect(yaml.contains("/run/secrets/db_password"), "config export includes resolved secret target")
        expect(!yaml.contains("placeholder-secret"), "config export redacts secret contents")
        expect(!yaml.contains("app_setting="), "config export redacts config contents")
    }

    mutating func runSecretsMergeTests() throws {
        let base = try ComposeParser.parse(fileURL: Self.fixtureURL("secrets-compose.yml"))
        let overrideURL = Self.fixtureURL("merge/secrets-override-compose.yml")
        let merged = try ComposeParser.parse(fileURLs: [
            Self.fixtureURL("secrets-compose.yml"),
            overrideURL
        ])
        expect(merged.secrets["db_password"]?.file == "./secrets/override.txt", "secrets merge override wins")
        expect(
            merged.services["app"]?.secrets.first?.resolvedTarget(kind: .secret) == "/run/secrets/custom",
            "service secret merge by source"
        )
        _ = base
    }
}
