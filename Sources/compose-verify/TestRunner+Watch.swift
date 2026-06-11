import ComposeCore
import ContainerAPIClient
import ContainerResource
import Containerization
import ContainerizationOCI
import Foundation

extension TestRunner {
    mutating func runWatchTests() throws {
        try runWatchDecodeTests()
        try runWatchValidationTests()
        runWatchPathMappingTests()
        runWatchIgnoreTests()
        runWatchDebouncerTests()
        try runWatchRuntimeTests()
        try runWatchResilienceTests()
    }

    private mutating func runWatchDecodeTests() throws {
        let fixture = try ComposeParser.parse(fileURL: Self.fixtureURL("develop-watch-compose.yml"))
        let watch = fixture.services["web"]?.develop?.watch
        expect(watch?.count == 1, "develop.watch decode count")
        expect(watch?[0].action == .sync, "develop.watch sync action")
        expect(watch?[0].target == "/usr/share/nginx/html", "develop.watch target")
        expect(watch?[0].initialSync == true, "develop.watch initial_sync")
        expect(watch?[0].ignore == ["node_modules/"], "develop.watch ignore")

        let restartFixture = try ComposeParser.parse(
            fileURL: Self.fixtureURL("develop-watch-restart-compose.yml")
        )
        expect(restartFixture.services["web"]?.develop?.watch[0].action == .syncRestart, "sync+restart decode")

        let mergeBaseURL = Self.fixtureURL("develop-watch-merge/base.yml")
        let mergeOverrideURL = Self.fixtureURL("develop-watch-merge/override.yml")
        let merged = try ComposeParser.parse(fileURLs: [mergeBaseURL, mergeOverrideURL])
        expect(merged.services["web"]?.develop?.watch.count == 1, "develop override replaces watch list")
        expect(
            merged.services["web"]?.develop?.watch[0].action == .syncRestart,
            "develop override watch action"
        )
        expect(
            merged.services["web"]?.develop?.watch[0].path == "./override-html",
            "develop override watch path"
        )
    }

    private mutating func runWatchValidationTests() throws {
        try runWatchActionValidationTests()
        try runWatchPathValidationTests()
    }

    private mutating func runWatchActionValidationTests() throws {
        let fixturesDirectory = Self.fixtureURL("develop-watch-compose.yml").deletingLastPathComponent()

        expectComposeError(
            "rebuild rejected",
            matching: { if case .invalidField("develop.watch", _) = $0 { true } else { false } },
            body: {
                _ = try WatchPathValidator.validateRules(
                    serviceName: "web",
                    develop: try ComposeParser.parse(
                        fileURL: Self.fixtureURL("develop-watch-rebuild-compose.yml")
                    ).services["web"]?.develop,
                    composeDirectory: fixturesDirectory
                )
            }
        )

        expectComposeError(
            "missing target",
            matching: { if case .invalidField("develop.watch.target", _) = $0 { true } else { false } },
            body: {
                _ = try WatchPathValidator.validateRules(
                    serviceName: "web",
                    develop: try ComposeParser.parse(
                        fileURL: Self.fixtureURL("develop-watch-missing-target-compose.yml")
                    ).services["web"]?.develop,
                    composeDirectory: fixturesDirectory
                )
            }
        )

        expectComposeError(
            "target escape",
            matching: { if case .invalidField("develop.watch.target", _) = $0 { true } else { false } },
            body: {
                _ = try WatchPathValidator.validateRules(
                    serviceName: "web",
                    develop: try ComposeParser.parse(
                        fileURL: Self.fixtureURL("develop-watch-escape-compose.yml")
                    ).services["web"]?.develop,
                    composeDirectory: fixturesDirectory
                )
            }
        )
    }

    private mutating func runWatchPathValidationTests() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("compose-watch-escape-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let projectDir = tempRoot.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let escapeRule = ComposeDevelop(
            watch: [
                ComposeWatchRule(
                    path: "../outside",
                    target: "/app",
                    action: .sync
                )
            ]
        )
        expectComposeError(
            "relative path escape",
            matching: { if case .invalidField("develop.watch.path", _) = $0 { true } else { false } },
            body: {
                _ = try WatchPathValidator.validateRules(
                    serviceName: "web",
                    develop: escapeRule,
                    composeDirectory: projectDir
                )
            }
        )
    }

    private mutating func runWatchPathMappingTests() {
        let watchRoot = URL(fileURLWithPath: "/project/html")
        let changed = URL(fileURLWithPath: "/project/html/index.html")
        do {
            let destination = try WatchPathValidator.containerDestination(
                watchRoot: watchRoot,
                containerTarget: "/usr/share/nginx/html",
                changedPath: changed
            )
            expect(destination == "/usr/share/nginx/html/index.html", "path mapping preserves relative suffix")
        } catch {
            fputs("FAIL: path mapping: \(error)\n", stderr)
            failures += 1
        }
    }

    private mutating func runWatchIgnoreTests() {
        expect(
            WatchPathValidator.isIgnored(relativePath: "node_modules/pkg/index.js", patterns: ["node_modules/"]),
            "ignore prefix matches nested file"
        )
        expect(
            !WatchPathValidator.isIgnored(relativePath: "src/main.swift", patterns: ["node_modules/"]),
            "ignore prefix skips unrelated paths"
        )
    }

    private mutating func runWatchDebouncerTests() {
        var debouncer = WatchDebouncer(window: .milliseconds(200))
        let clock = ContinuousClock()
        let start = clock.now
        let path = URL(fileURLWithPath: "/tmp/example.txt")
        for _ in 0..<5 {
            debouncer.schedule(ruleID: "web#0", hostPath: path, at: start)
        }
        expect(debouncer.drainReady(at: start).isEmpty, "debouncer holds burst until window elapses")
        let ready = debouncer.drainReady(at: start + .milliseconds(200))
        expect(ready.count == 1, "debouncer coalesces burst into one flush")
    }
}
