import ComposeCore
import Foundation

extension TestRunner {
    mutating func runProjectOptionsTests() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("compose-verify-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let previousCWD = FileManager.default.currentDirectoryPath
        FileManager.default.changeCurrentDirectoryPath(tempDir.path)
        defer { FileManager.default.changeCurrentDirectoryPath(previousCWD) }

        let previousComposeFile = ProcessInfo.processInfo.environment["COMPOSE_FILE"]
        let previousProjectName = ProcessInfo.processInfo.environment["COMPOSE_PROJECT_NAME"]
        defer {
            restoreEnvironmentVariable("COMPOSE_FILE", value: previousComposeFile)
            restoreEnvironmentVariable("COMPOSE_PROJECT_NAME", value: previousProjectName)
        }

        let defaultFileURLs = try ComposeFileResolution.resolvedIfPresent(
            files: [ComposeFileResolution.defaultFileName]
        )
        expect(defaultFileURLs == nil, "default compose file optional when absent")

        expectComposeError(
            "explicit missing compose file",
            matching: { if case .fileNotFound = $0 { true } else { false } },
            body: {
                _ = try ComposeFileResolution.resolvedIfPresent(files: ["missing-compose.yml"])
            }
        )

        let mergeBase = Self.fixtureURL("merge/base.yml")
        let mergeOverride = Self.fixtureURL("merge/override.yml")
        let resolved = try ComposeFileResolution.resolved(files: [
            mergeBase.path,
            mergeOverride.path
        ])
        expect(resolved.count == 2, "multi-file resolution count")
        expect(resolved[0].lastPathComponent == "base.yml", "multi-file resolution order")
        expect(resolved[1].lastPathComponent == "override.yml", "multi-file resolution second file")

        expectComposeError(
            "missing file mid-chain",
            matching: { if case .fileNotFound = $0 { true } else { false } },
            body: {
                _ = try ComposeFileResolution.resolved(files: [mergeBase.path, "missing-compose.yml"])
            }
        )

        try "services: {}\n".write(
            to: tempDir.appendingPathComponent("compose.yaml"),
            atomically: true,
            encoding: .utf8
        )
        try "services: {}\n".write(
            to: tempDir.appendingPathComponent("compose.override.yaml"),
            atomically: true,
            encoding: .utf8
        )
        try "services: {}\n".write(
            to: tempDir.appendingPathComponent("docker-compose.yml"),
            atomically: true,
            encoding: .utf8
        )

        let discovered = try ComposeFileResolution.discover(cliFiles: [])
        expect(
            discovered == ["compose.yaml", "compose.override.yaml"],
            "discover compose.yaml and paired override"
        )

        setEnvironmentVariable("COMPOSE_FILE", value: "custom.yml:custom-2.yml")
        try "services: {}\n".write(
            to: tempDir.appendingPathComponent("custom.yml"),
            atomically: true,
            encoding: .utf8
        )
        try "services: {}\n".write(
            to: tempDir.appendingPathComponent("custom-2.yml"),
            atomically: true,
            encoding: .utf8
        )
        let composeFileDiscovered = try ComposeFileResolution.discover(cliFiles: [])
        expect(
            composeFileDiscovered == ["custom.yml", "custom-2.yml"],
            "discover COMPOSE_FILE colon-separated paths"
        )

        let cliOnly = try ComposeFileResolution.discover(cliFiles: ["docker-compose.yml"])
        expect(cliOnly == ["docker-compose.yml"], "explicit -f ignores COMPOSE_FILE")

        setEnvironmentVariable("COMPOSE_FILE", value: "a.yml::b.yml")
        expectComposeError(
            "COMPOSE_FILE empty segment",
            matching: { if case .invalidComposeFilePath = $0 { true } else { false } },
            body: {
                _ = try ComposeFileResolution.discover(cliFiles: [])
            }
        )

        try runProjectNamingTests()
    }

    mutating func runProjectNamingTests() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("compose-verify-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let composeFileURL = tempDir.appendingPathComponent("docker-compose.yml")
        try "name: My-Project\nservices: {}\n".write(to: composeFileURL, atomically: true, encoding: .utf8)

        let fromComposeName = try ProjectNameResolver.resolve(
            cliProjectName: nil,
            environment: [:],
            composeName: "My-Project",
            firstFileURL: composeFileURL
        )
        expect(fromComposeName == "my-project", "normalize compose name field")

        let previousProjectName = ProcessInfo.processInfo.environment["COMPOSE_PROJECT_NAME"]
        defer { restoreEnvironmentVariable("COMPOSE_PROJECT_NAME", value: previousProjectName) }

        setEnvironmentVariable("COMPOSE_PROJECT_NAME", value: "Env_Project")
        let fromEnv = try ProjectNameResolver.resolve(
            cliProjectName: nil,
            composeName: "ignored",
            firstFileURL: composeFileURL
        )
        expect(fromEnv == "env_project", "COMPOSE_PROJECT_NAME precedence over compose name")

        let fromCLI = try ProjectNameResolver.resolve(
            cliProjectName: "cli-project",
            composeName: "ignored",
            firstFileURL: composeFileURL
        )
        expect(fromCLI == "cli-project", "-p precedence over env and compose name")

        expectComposeError(
            "invalid project name",
            matching: { if case .invalidProjectName = $0 { true } else { false } },
            body: {
                _ = try ProjectNameResolver.normalize("===")
            }
        )
    }

    private func setEnvironmentVariable(_ name: String, value: String) {
        setenv(name, value, 1)
    }

    private func restoreEnvironmentVariable(_ name: String, value: String?) {
        if let value {
            setenv(name, value, 1)
        } else {
            unsetenv(name)
        }
    }
}
