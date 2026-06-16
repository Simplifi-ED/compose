import ComposeCore
import ContainerCommands
import ContainerizationError
import Foundation

struct TestRunner {
    var failures = 0

    mutating func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String,
        file: String = #file,
        line: Int = #line
    ) {
        if !condition() {
            fputs("FAIL \(file):\(line): \(message)\n", stderr)
            failures += 1
        }
    }

    mutating func expectThrows<T: Error>(_ type: T.Type, _ message: String, _ body: () throws -> Void) {
        do {
            try body()
            fputs("FAIL: expected throw for \(message)\n", stderr)
            failures += 1
        } catch {
            guard error is T else {
                fputs("FAIL: wrong error type for \(message): \(error)\n", stderr)
                failures += 1
                return
            }
        }
    }

    mutating func expectComposeError(
        _ message: String,
        matching predicate: (ComposeError) -> Bool,
        body: () throws -> Void
    ) {
        do {
            try body()
            fputs("FAIL: expected throw for \(message)\n", stderr)
            failures += 1
        } catch let error as ComposeError {
            guard predicate(error) else {
                fputs("FAIL: wrong ComposeError case for \(message): \(error)\n", stderr)
                failures += 1
                return
            }
        } catch {
            fputs("FAIL: wrong error type for \(message): \(error)\n", stderr)
            failures += 1
        }
    }

    static func fixtureURL(_ name: String) -> URL {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return repoRoot.appendingPathComponent("Tests/composeTests/Fixtures/\(name)")
    }

    mutating func runParserTests() throws {
        let minimal = try ComposeParser.parse(fileURL: Self.fixtureURL("minimal-compose.yml"))
        expect(minimal.services.count == 1, "minimal service count")
        let web = minimal.services["web"]
        expect(web?.image == "docker.io/library/alpine:latest", "minimal image")
        expect(web?.command == .string("sleep 300"), "minimal command")
        expect(web?.ports == ["18080:80"], "minimal ports")

        let full = try ComposeParser.parse(fileURL: Self.fixtureURL("full-compose.yml"))
        expect(full.name == "demo", "full project name")
        expect(full.services.count == 2, "full service count")
        expect(full.services["api"]?.command == .list(["sleep", "600"]), "api command list")
        expect(full.services["api"]?.environment == .map(["FOO": "bar"]), "api environment map")
        expect(full.services["worker"]?.environment == .list(["BAZ=qux"]), "worker environment list")
        expect(full.services["worker"]?.containerName == "custom-worker", "worker container name")

        let missingImageURL = Self.fixtureURL("missing-image-compose.yml")
        expectThrows(ComposeError.self, "missing image") {
            _ = try ComposeParser.parse(fileURL: missingImageURL)
        }
        expectThrows(ComposeError.self, "missing file") {
            _ = try ComposeParser.parse(fileURL: URL(fileURLWithPath: "/tmp/does-not-exist-compose.yml"))
        }

        let volumesFixture = try ComposeParser.parse(fileURL: Self.fixtureURL("volumes-compose.yml"))
        expect(volumesFixture.services["web"]?.volumes == ["./data:/mnt/data"], "volumes fixture decode")
    }

    mutating func runLabelTests() {
        let flags = ComposeLabels.runFlags(projectName: "demo", serviceName: "web", containerNumber: 2)
        let expected = [
            "-l", "com.docker.compose.project=demo",
            "-l", "com.docker.compose.service=web",
            "-l", "com.docker.compose.container-number=2"
        ]
        expect(flags == expected, "run label flags")
    }

    mutating func runDependencyTests() throws {
        try runDependencyDecodeTests()
        try runDependencyLayerTests()
        try runDependencyErrorTests()
    }

    mutating func runDependencyDecodeTests() throws {
        let dependsFixture = try ComposeParser.parse(fileURL: Self.fixtureURL("depends-compose.yml"))
        expect(dependsFixture.services["web"]?.dependsOn.serviceNames == ["db", "cache"], "depends_on decode")
        expect(dependsFixture.services["api"]?.dependsOn.serviceNames == ["db"], "depends_on single dep decode")
        expect(dependsFixture.services["db"]?.dependsOn == [], "depends_on default empty")
    }

    mutating func runDependencyLayerTests() throws {
        let fixturesDirectory = Self.fixtureURL("depends-compose.yml").deletingLastPathComponent()
        let dependsFixture = try ComposeParser.parse(fileURL: Self.fixtureURL("depends-compose.yml"))

        let layers = try ServicePlanner.startupLayers(
            for: dependsFixture,
            projectName: "demo",
            composeDirectory: fixturesDirectory
        )
        expect(layers.count == 2, "depends layers wave count")
        expect(
            Set(layers[0].map(\.serviceName)) == ["cache", "db"],
            "depends layer 0 independent services"
        )
        expect(
            Set(layers[1].map(\.serviceName)) == ["api", "web"],
            "depends layer 1 dependents"
        )

        let flattened = layers.flatMap { $0 }
        let dbIndex = flattened.firstIndex { $0.serviceName == "db" }
        let webIndex = flattened.firstIndex { $0.serviceName == "web" }
        expect(dbIndex != nil && webIndex != nil, "depends flattened contains db and web")
        if let dbIndex, let webIndex {
            expect(dbIndex < webIndex, "depends db before web")
        }

        let duplicateDependsFixture = try ComposeParser.parse(fileURL: Self.fixtureURL("duplicate-depends-compose.yml"))
        let duplicateLayers = try ServicePlanner.startupLayers(
            for: duplicateDependsFixture,
            projectName: "demo",
            composeDirectory: fixturesDirectory
        )
        expect(duplicateLayers.count == 2, "duplicate depends_on layers wave count")
        expect(duplicateLayers[1].map(\.serviceName) == ["web"], "duplicate depends_on single dependent wave")
    }

    mutating func runDependencyErrorTests() throws {
        expectComposeError(
            "unknown dependency",
            matching: { if case .unknownDependency = $0 { true } else { false } },
            body: {
                _ = try ComposeParser.parse(fileURL: Self.fixtureURL("unknown-dependency-compose.yml"))
            }
        )

        expectComposeError(
            "circular dependency",
            matching: { if case .circularDependency = $0 { true } else { false } },
            body: {
                _ = try ComposeParser.parse(fileURL: Self.fixtureURL("circular-dependency-compose.yml"))
            }
        )

        expectComposeError(
            "self dependency",
            matching: { if case .circularDependency = $0 { true } else { false } },
            body: {
                _ = try ComposeParser.parse(fileURL: Self.fixtureURL("self-dependency-compose.yml"))
            }
        )

        let longformFixture = try ComposeParser.parse(fileURL: Self.fixtureURL("longform-depends-compose.yml"))
        let webDependency = longformFixture.services["web"]?.dependsOn.first
        expect(webDependency?.service == "db", "longform depends_on service decode")
        expect(webDependency?.condition == .serviceHealthy, "longform depends_on condition decode")
    }
}

var runner = TestRunner()

do {
    try runner.runParserTests()
    try runner.runDotEnvTests()
    try runner.runSubstitutionTests()
    try runner.runPlannerTests()
    try runner.runSSHTests()
    try runner.runDependencyTests()
    try runner.runHealthcheckTests()
    try runner.runProfileTests()
    try runner.runScaleTests()
    try runner.runResourceLimitsTests()
    runner.runParallelTests()
    try runner.runMergeTests()
    try runner.runConfigTests()
    try runner.runArchiveTests()
    try runner.runFileMountsTests()
    try runner.runIncludeTests()
    try runner.runWatchTests()
    try runner.runProjectOptionsTests()
    try runner.runShutdownLayerTests()
    try runner.runOrphanTests()
    try runner.runVolumePurgeTests()
    try runner.runReadOnlyVolumeTests()
    try runner.runNetworkTests()
    try runner.runHostDNSTests()
    try runner.runNamedVolumeTests()
    runner.runDiskTrimTests()
    try runner.runDryRunTests()
    try runner.runPauseTests()
    try runner.runBuildTests()
    try runner.runPlatformTests()
    runner.runLabelTests()
    runner.runRollbackTests()
    runner.runTeardownErrorTests()
    runner.runTerminalTests()
    runner.runDoctorTests()
    runner.runProgressTests()
    runner.runPsTests()
    runner.runLogsTests()
    runner.runEventsTests()
    runner.runTopTests()
    try runner.runAttachTests()
    runner.runExecTests()
    runner.runTerminalResizeTests()
    runner.runCpTests()
    runner.runMachineTests()
    runner.runRunTests()
    runner.runSignalsTests()
    runner.runOsLogConfigurationTests()
    runner.runXPCTests()
} catch {
    fputs("FAIL: unexpected error: \(error)\n", stderr)
    runner.failures += 1
}

if runner.failures > 0 {
    fputs("\(runner.failures) verification failure(s)\n", stderr)
    exit(1)
}

print("compose-verify: all checks passed")
