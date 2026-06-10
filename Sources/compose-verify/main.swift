import ComposeCore
import Foundation

struct TestRunner {
    var failures = 0

    mutating func expect(_ condition: @autoclosure () -> Bool, _ message: String, file: String = #file, line: Int = #line) {
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
    }

    mutating func runPlannerTests() throws {
        let service = ComposeService(
            image: "docker.io/library/alpine:latest",
            command: .string("sleep 300"),
            ports: ["18080:80"],
            environment: .map(["FOO": "bar"]),
            containerName: nil
        )
        let plan = try ServicePlanner.plan(serviceName: "web", service: service, projectName: "demo")
        expect(plan.containerID == "demo_web", "planner container id")
        expect(plan.runArguments.contains("-d"), "planner detach")
        expect(plan.runArguments.contains("127.0.0.1:18080:80"), "planner publish")

        let named = ComposeService(
            image: "docker.io/library/alpine:latest",
            command: nil,
            ports: [],
            environment: nil,
            containerName: "custom-worker"
        )
        let namedPlan = try ServicePlanner.plan(serviceName: "worker", service: named, projectName: "demo")
        expect(namedPlan.containerID == "custom-worker", "planner container name override")

        let publishFlag = try ServicePlanner.publishFlag(for: "8080:80/tcp")
        expect(publishFlag == "127.0.0.1:8080:80/tcp", "planner protocol suffix")
        expectThrows(ComposeError.self, "invalid port") {
            _ = try ServicePlanner.publishFlag(for: "not-a-port")
        }
    }
}

var runner = TestRunner()

do {
    try runner.runParserTests()
    try runner.runPlannerTests()
} catch {
    fputs("FAIL: unexpected error: \(error)\n", stderr)
    runner.failures += 1
}

if runner.failures > 0 {
    fputs("\(runner.failures) verification failure(s)\n", stderr)
    exit(1)
}

print("compose-verify: all checks passed")
