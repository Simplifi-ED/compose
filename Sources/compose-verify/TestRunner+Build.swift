import ComposeCore
import ContainerCommands
import Foundation

extension TestRunner {
    mutating func runBuildTests() throws {
        try runBuildDecodeTests()
        try runBuildImageResolverTests()
        try runBuildValidatorTests()
        try runBuildValidatorEscapeTests()
        try runBuildValidatorAbsoluteContextTests()
        try runBuildPlannerTests()
        try runBuildConfigTests()
        try runBuildRunDependencyTests()
        try runBuildDryRunTests()
        try runBuildArgumentMappingTests()
    }

    private mutating func runBuildDecodeTests() throws {
        let shortForm = try ComposeParser.parse(fileURL: Self.fixtureURL("build-compose.yml"))
        let web = shortForm.services["web"]
        expect(web?.build?.context == "./build-fixture", "build short-form context decode")
        expect(web?.image == nil, "build-only service has no image in parse")

        let objectForm = try ComposeParser.parse(fileURL: Self.fixtureURL("build-with-image-compose.yml"))
        let tagged = objectForm.services["web"]
        expect(tagged?.image == "custom_web_tag", "build with explicit image tag")
        expect(tagged?.build?.context == "./build-fixture", "build object context decode")

        let argsForm = try ComposeParser.parse(fileURL: Self.fixtureURL("build-args-compose.yml"))
        expect(argsForm.services["web"]?.build?.args["APP_VERSION"] == "1.0.0", "build args decode")
    }

    private mutating func runBuildImageResolverTests() throws {
        let service = ComposeService(
            image: nil,
            build: ComposeBuild(context: "."),
            command: .string("sleep 300"),
            ports: [],
            environment: nil,
            containerName: nil
        )
        let tag = try BuildImageResolver.resolvedImageTag(
            projectName: "demo",
            serviceName: "web",
            service: service
        )
        expect(tag == "demo_web", "default build image tag uses project_service")

        let explicit = ComposeService(
            image: "custom",
            build: ComposeBuild(context: "."),
            command: .string("sleep 300"),
            ports: [],
            environment: nil,
            containerName: nil
        )
        let explicitTag = try BuildImageResolver.resolvedImageTag(
            projectName: "demo",
            serviceName: "web",
            service: explicit
        )
        expect(explicitTag == "custom", "explicit image wins over default build tag")
    }

    private mutating func runBuildValidatorTests() throws {
        let fixturesDirectory = Self.fixtureURL("build-compose.yml").deletingLastPathComponent()
        let composeFile = try ComposeParser.parse(fileURL: Self.fixtureURL("build-compose.yml"))
        expectComposeError(
            "missing build context",
            matching: {
                if case .buildContextNotFound(path: "./missing-build-context", service: "web") = $0 {
                    true
                } else {
                    false
                }
            },
            body: {
                _ = try BuildRunner.plans(
                    composeFile: try ComposeParser.parse(
                        fileURL: Self.fixtureURL("build-missing-context-compose.yml")
                    ),
                    projectName: "demo",
                    composeDirectory: fixturesDirectory,
                    activeProfiles: []
                )
            }
        )

        _ = try BuildRunner.plans(
            composeFile: composeFile,
            projectName: "demo",
            composeDirectory: fixturesDirectory,
            activeProfiles: []
        )
        expect(true, "valid build context passes validation")
    }

    private mutating func runBuildValidatorEscapeTests() throws {
        let fixturesDirectory = Self.fixtureURL("build-compose.yml").deletingLastPathComponent()
        expectComposeError(
            "build context escapes compose directory",
            matching: {
                if case .invalidField("build.context", _) = $0 { true } else { false }
            },
            body: {
                _ = try BuildRunner.plans(
                    composeFile: try ComposeParser.parse(
                        fileURL: Self.fixtureURL("build-escape-context-compose.yml")
                    ),
                    projectName: "demo",
                    composeDirectory: fixturesDirectory,
                    activeProfiles: []
                )
            }
        )

        expectComposeError(
            "build dockerfile escapes build context",
            matching: {
                if case .invalidField("build.dockerfile", _) = $0 { true } else { false }
            },
            body: {
                _ = try BuildRunner.plans(
                    composeFile: try ComposeParser.parse(
                        fileURL: Self.fixtureURL("build-escape-dockerfile-compose.yml")
                    ),
                    projectName: "demo",
                    composeDirectory: fixturesDirectory,
                    activeProfiles: []
                )
            }
        )

    }

    private mutating func runBuildValidatorAbsoluteContextTests() throws {
        let fixturesDirectory = Self.fixtureURL("build-compose.yml").deletingLastPathComponent()
        expectComposeError(
            "absolute build context escapes compose directory",
            matching: {
                if case .invalidField("build.context", _) = $0 { true } else { false }
            },
            body: {
                let outside = FileManager.default.temporaryDirectory
                    .appendingPathComponent("compose-verify-build-outside-\(UUID().uuidString)")
                defer { try? FileManager.default.removeItem(at: outside) }
                try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
                let composePath = fixturesDirectory.appendingPathComponent("absolute-escape-build.yml")
                try """
                services:
                  web:
                    build:
                      context: \(outside.path)
                    command: sleep 300
                """.write(to: composePath, atomically: true, encoding: .utf8)
                defer { try? FileManager.default.removeItem(at: composePath) }
                _ = try BuildRunner.plans(
                    composeFile: try ComposeParser.parse(fileURL: composePath),
                    projectName: "demo",
                    composeDirectory: fixturesDirectory,
                    activeProfiles: []
                )
            }
        )

        let insideContext = fixturesDirectory
            .appendingPathComponent("build-fixture")
            .standardizedFileURL
            .path
        let insideComposePath = fixturesDirectory.appendingPathComponent("absolute-inside-build.yml")
        try """
        services:
          web:
            build:
              context: \(insideContext)
            command: sleep 300
        """.write(to: insideComposePath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: insideComposePath) }
        _ = try BuildRunner.plans(
            composeFile: try ComposeParser.parse(fileURL: insideComposePath),
            projectName: "demo",
            composeDirectory: fixturesDirectory,
            activeProfiles: []
        )
        expect(true, "absolute build context inside compose directory passes validation")
    }

    private mutating func runBuildPlannerTests() throws {
        let fixturesDirectory = Self.fixtureURL("build-compose.yml").deletingLastPathComponent()
        let composeFile = try ComposeParser.parse(fileURL: Self.fixtureURL("build-compose.yml"))
        let layers = try ServicePlanner.startupLayers(
            for: composeFile,
            projectName: "demo",
            composeDirectory: fixturesDirectory,
            activeProfiles: [],
            scaleOverrides: [:]
        )
        let web = layers.flatMap { $0 }.first { $0.serviceName == "web" }
        expect(web?.image == "demo_web", "planner resolves build-only service image tag")
    }

    private mutating func runBuildConfigTests() throws {
        let fileURLs = [Self.fixtureURL("build-compose.yml")]
        let resolved = try ComposeConfigResolver.resolve(
            fileURLs: fileURLs,
            projectName: "demo",
            activeProfiles: [],
            scaleOverrides: [:]
        )
        expect(resolved.services["web"]?.image == "demo_web", "config injects resolved image for build service")
        expect(resolved.services["web"]?.build != nil, "config keeps build block")

        let yaml = try ComposeConfigResolver.resolveOutput(
            fileURLs: fileURLs,
            projectName: "demo",
            activeProfiles: [],
            scaleOverrides: [:]
        )!
        expect(yaml.contains("image: demo_web"), "config yaml shows resolved image tag")

        let missingContext = try ComposeConfigResolver.resolve(
            fileURLs: [Self.fixtureURL("build-missing-context-compose.yml")],
            projectName: "demo",
            activeProfiles: [],
            scaleOverrides: [:]
        )
        expect(
            missingContext.services["web"]?.image == "demo_web",
            "config resolves build image without on-disk context"
        )
    }

    private mutating func runBuildRunDependencyTests() throws {
        let fixturesDirectory = Self.fixtureURL("build-run-deps-compose.yml").deletingLastPathComponent()
        let composeFile = try ComposeParser.parse(fileURL: Self.fixtureURL("build-run-deps-compose.yml"))
        let plans = try BuildRunner.runBuildPlans(
            targetServiceName: "web",
            composeFile: composeFile,
            projectName: "demo",
            composeDirectory: fixturesDirectory
        )
        expect(plans.map(\.serviceName) == ["api", "web"], "run builds dependency chain in topological order")
    }

    private mutating func runBuildDryRunTests() throws {
        let fixturesDirectory = Self.fixtureURL("build-compose.yml").deletingLastPathComponent()
        let composeFile = try ComposeParser.parse(fileURL: Self.fixtureURL("build-compose.yml"))
        let buildPlans = try BuildRunner.plans(
            composeFile: composeFile,
            projectName: "demo",
            composeDirectory: fixturesDirectory,
            activeProfiles: []
        )
        let manifest = DryRunManifest()
        for plan in buildPlans {
            blockingAwait {
                await manifest.recordBuild(
                    service: plan.serviceName,
                    tag: plan.tag,
                    context: plan.contextDisplayPath,
                    dockerfile: plan.dockerfile
                )
            }
        }
        let lines = blockingAwait { await manifest.sortedLines() }
        expect(lines.contains(where: { $0.contains("[DRY-RUN] build image \"demo_web\"") }), "dry-run build line")
        expect(!lines.contains(where: { $0.contains("APP_VERSION") }), "dry-run build line omits arg values")
    }

    private mutating func runBuildArgumentMappingTests() throws {
        let fixturesDirectory = Self.fixtureURL("build-args-compose.yml").deletingLastPathComponent()
        let composeFile = try ComposeParser.parse(fileURL: Self.fixtureURL("build-args-compose.yml"))
        let plans = try BuildRunner.plans(
            composeFile: composeFile,
            projectName: "demo",
            composeDirectory: fixturesDirectory,
            activeProfiles: []
        )
        guard let plan = plans.first else {
            expect(false, "build args fixture produces a build plan")
            return
        }
        let dockerfilePath = try BuildRunner.resolvedDockerfilePath(for: plan)
        expect(
            dockerfilePath?.hasSuffix("/build-fixture/Dockerfile") == true,
            "dockerfile path resolves against context"
        )
        let arguments = try BuildRunner.buildArguments(for: plan, progress: .plain)
        _ = try Application.BuildCommand.parse(arguments)
        expect(arguments.contains("demo_web"), "build args include image tag")
        expect(arguments.contains("--build-arg"), "build args include build-arg flag")
        let joined = arguments.joined(separator: " ")
        expect(!joined.contains("secret"), "build arg values not echoed in argv logging surface")
    }
}
