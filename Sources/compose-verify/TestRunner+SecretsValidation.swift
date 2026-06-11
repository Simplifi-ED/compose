import ComposeCore
import Foundation

extension TestRunner {
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
            "missing config file",
            matching: {
                if case .resourceFileNotFound(let path, .config) = $0 {
                    return path == "./secrets/missing-config.txt"
                }
                return false
            },
            body: {
                _ = try ComposeParser.parse(fileURL: Self.fixtureURL("missing-config-compose.yml"))
            }
        )

        expectComposeError(
            "undefined secret",
            matching: {
                if case .undefinedResource(name: "missing_secret", kind: .secret) = $0 { true } else { false }
            },
            body: {
                _ = try ComposeParser.parse(fileURL: Self.fixtureURL("undefined-secret-compose.yml"))
            }
        )

        expectComposeError(
            "undefined config",
            matching: {
                if case .undefinedResource(name: "missing_config", kind: .config) = $0 { true } else { false }
            },
            body: {
                _ = try ComposeParser.parse(fileURL: Self.fixtureURL("undefined-config-compose.yml"))
            }
        )
    }

    mutating func runSecretsHardeningTests() throws {
        for kind in ComposeFileMountKind.allCases {
            try runFileMountHardeningTests(for: kind)
        }
    }

    mutating func runStartupLayersMountValidationTests() throws {
        let fixturesDirectory = Self.fixtureURL("secrets-compose.yml").deletingLastPathComponent()
        let service = ComposeService(
            image: "docker.io/library/alpine:3.20",
            command: nil,
            ports: [],
            environment: nil,
            containerName: nil,
            configs: [ComposeServiceMount(source: "ghost_config")]
        )
        let composeFile = ComposeFile(
            name: nil,
            services: ["app": service]
        )
        expectComposeError(
            "startupLayers validates undefined config",
            matching: {
                if case .undefinedResource(name: "ghost_config", kind: .config) = $0 { true } else { false }
            },
            body: {
                _ = try ServicePlanner.startupLayers(
                    for: composeFile,
                    projectName: "demo",
                    composeDirectory: fixturesDirectory
                )
            }
        )
    }

    private mutating func runFileMountHardeningTests(for kind: ComposeFileMountKind) throws {
        let prefix = kind.rootFieldName
        expectInvalidResourceField(
            "\(prefix) absolute path",
            field: prefix,
            reasonContains: "absolute file paths aren't supported",
            fixture: "absolute-\(kind == .secret ? "secret" : "config")-compose.yml"
        )
        expectInvalidResourceField(
            "\(prefix) path escape",
            field: prefix,
            reasonContains: "resolves outside the compose file directory",
            fixture: "escape-\(kind == .secret ? "secret" : "config")-compose.yml"
        )
        let sharedTarget = kind == .secret ? "/run/secrets/shared" : "/run/configs/shared"
        expectInvalidResourceField(
            "duplicate \(prefix) target",
            field: prefix,
            reasonContains: "maps multiple \(prefix) to '\(sharedTarget)'",
            fixture: "duplicate-\(kind == .secret ? "secret" : "config")-target-compose.yml"
        )
    }

    private mutating func expectInvalidResourceField(
        _ label: String,
        field: String,
        reasonContains: String,
        fixture: String
    ) {
        expectComposeError(
            label,
            matching: {
                if case .invalidField(field, let reason) = $0 {
                    return reason.contains(reasonContains)
                }
                return false
            },
            body: {
                _ = try ComposeParser.parse(fileURL: Self.fixtureURL(fixture))
            }
        )
    }
}
