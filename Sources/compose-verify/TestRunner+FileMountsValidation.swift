import ComposeCore
import Foundation

extension TestRunner {
    mutating func runFileMountsValidationTests() throws {
        try runFileMountsResourceErrorTests()
        try runProfileScopedMountValidationTests()
    }

    private mutating func runFileMountsResourceErrorTests() throws {
        try runFileMountsMissingFileTests()
        try runFileMountsUndefinedResourceTests()
    }

    private mutating func runFileMountsMissingFileTests() throws {
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
                _ = try ComposeConfigResolver.resolve(
                    fileURLs: [Self.fixtureURL("missing-config-compose.yml")],
                    activeProfiles: [],
                    scaleOverrides: [:]
                )
            }
        )
    }

    private mutating func runFileMountsUndefinedResourceTests() throws {
        expectComposeError(
            "undefined secret",
            matching: {
                if case .undefinedResource(name: "missing_secret", kind: .secret) = $0 { true } else { false }
            },
            body: {
                _ = try ComposeConfigResolver.resolve(
                    fileURLs: [Self.fixtureURL("undefined-secret-compose.yml")],
                    activeProfiles: [],
                    scaleOverrides: [:]
                )
            }
        )

        expectComposeError(
            "undefined config",
            matching: {
                if case .undefinedResource(name: "missing_config", kind: .config) = $0 { true } else { false }
            },
            body: {
                _ = try ComposeConfigResolver.resolve(
                    fileURLs: [Self.fixtureURL("undefined-config-compose.yml")],
                    activeProfiles: [],
                    scaleOverrides: [:]
                )
            }
        )
    }

    mutating func runFileMountsHardeningTests() throws {
        for kind in ComposeFileMountKind.allCases {
            try runFileMountHardeningTests(for: kind)
        }
        try runCrossKindDuplicateTargetTest()
    }

    mutating func runStartupLayersMountValidationTests() throws {
        let fixturesDirectory = Self.fixtureURL("file-mounts-compose.yml").deletingLastPathComponent()
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

    private mutating func runProfileScopedMountValidationTests() throws {
        let fixturesDirectory = Self.fixtureURL("profiled-broken-mount-compose.yml").deletingLastPathComponent()
        let composeFile = try ComposeParser.parse(
            fileURL: Self.fixtureURL("profiled-broken-mount-compose.yml")
        )

        let defaultLayers = try ServicePlanner.startupLayers(
            for: composeFile,
            projectName: "demo",
            composeDirectory: fixturesDirectory,
            activeProfiles: []
        )
        expect(defaultLayers.map { $0.map(\.serviceName) } == [["web"]], "default up skips profiled broken mounts")

        expectComposeError(
            "active profile validates broken mounts",
            matching: {
                if case .resourceFileNotFound(let path, .config) = $0 {
                    return path == "./secrets/missing-config.txt"
                }
                return false
            },
            body: {
                _ = try ServicePlanner.startupLayers(
                    for: composeFile,
                    projectName: "demo",
                    composeDirectory: fixturesDirectory,
                    activeProfiles: ["debug"]
                )
            }
        )
    }

    private mutating func runCrossKindDuplicateTargetTest() throws {
        expectComposeError(
            "cross-kind duplicate target",
            matching: {
                if case .invalidField("secrets", let reason) = $0 {
                    return reason.contains("maps multiple configs/secrets to '/run/shared/mount'")
                }
                return false
            },
            body: {
                _ = try ComposeConfigResolver.resolve(
                    fileURLs: [Self.fixtureURL("cross-kind-target-compose.yml")],
                    activeProfiles: [],
                    scaleOverrides: [:]
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
            reasonContains: "maps multiple configs/secrets to '\(sharedTarget)'",
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
                _ = try ComposeConfigResolver.resolve(
                    fileURLs: [Self.fixtureURL(fixture)],
                    activeProfiles: [],
                    scaleOverrides: [:]
                )
            }
        )
    }
}
