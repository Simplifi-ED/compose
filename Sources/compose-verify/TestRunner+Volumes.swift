import ComposeCore
import Foundation

extension TestRunner {
    mutating func runVolumePurgeTests() throws {
        try runVolumePurgeCollectionTests()
        try runVolumePurgeSharedMountTests()
        try runVolumePurgeIntegrationTests()
    }

    mutating func runVolumePurgeCollectionTests() throws {
        let fixture = try ComposeParser.parse(fileURL: Self.fixtureURL("volumes-purge-compose.yml"))
        let fixtureDirectory = Self.fixtureURL("volumes-purge-compose.yml").deletingLastPathComponent()

        let allPaths = BindMountPurge.collectPurgeablePaths(
            composeFile: fixture,
            composeDirectory: fixtureDirectory,
            serviceNames: Set(fixture.services.keys)
        )
        let expectedDataPath = fixtureDirectory
            .appendingPathComponent("data")
            .standardizedFileURL
            .path
        expect(allPaths == [expectedDataPath], "collect relative bind-mount paths only")

        let webOnly = BindMountPurge.collectPurgeablePaths(
            composeFile: fixture,
            composeDirectory: fixtureDirectory,
            serviceNames: ["web"]
        )
        expect(webOnly == [expectedDataPath], "profile-scoped path collection limits services")

        let profilesFixture = try ComposeParser.parse(fileURL: Self.fixtureURL("profiles-compose.yml"))
        let profileServices = ProfileFilter.matchingServiceNames(
            from: profilesFixture.services,
            activeProfiles: ["debug"],
            includeAll: false
        )
        expect(profileServices == ["web", "db", "debugger"], "profile service names for volume scope")
    }

    mutating func runVolumePurgeSharedMountTests() throws {
        let fixture = try ComposeParser.parse(fileURL: Self.fixtureURL("volumes-purge-compose.yml"))
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("compose-verify-shared-mount-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let dataDirectory = root.appendingPathComponent("data")
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)

        let webPaths = BindMountPurge.collectPurgeablePaths(
            composeFile: fixture,
            composeDirectory: root,
            serviceNames: ["web"]
        )
        let cachePaths = BindMountPurge.collectPurgeablePaths(
            composeFile: fixture,
            composeDirectory: root,
            serviceNames: ["cache"]
        )
        let result = BindMountPurge.purge(
            paths: webPaths,
            composeDirectory: root,
            pathsInUseByRunningServices: Set(cachePaths)
        )
        expect(result.removed.isEmpty, "shared mount not purged while sibling service still running")
        expect(
            result.skipped.contains { $0.reason == .stillInUseByRunningContainer },
            "shared mount skipped as still in use"
        )
        expect(FileManager.default.fileExists(atPath: dataDirectory.path), "shared data directory preserved")
    }

    mutating func runVolumePurgeIntegrationTests() throws {
        try runVolumePurgeRemovalTests()
        try runVolumePurgeSymlinkEscapeTests()
    }

    mutating func runVolumePurgeRemovalTests() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("compose-verify-volumes-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let dataDirectory = root.appendingPathComponent("data")
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        let marker = dataDirectory.appendingPathComponent("marker.txt")
        try Data("purge-me".utf8).write(to: marker)

        let composeFile = ComposeFile(
            name: nil,
            services: [
                "web": ComposeService(
                    image: "docker.io/library/alpine:3.24",
                    command: .string("sleep 300"),
                    ports: [],
                    volumes: ["./data:/mnt/data"],
                    environment: nil,
                    containerName: nil
                )
            ]
        )
        let paths = BindMountPurge.collectPurgeablePaths(
            composeFile: composeFile,
            composeDirectory: root,
            serviceNames: ["web"]
        )
        expect(paths.count == 1, "integration collects one purge path")

        let composeYAML = root.appendingPathComponent("compose.yaml")
        try Data("services: {}\n".utf8).write(to: composeYAML)
        let result = BindMountPurge.purge(
            paths: paths,
            composeDirectory: root,
            protectedPaths: BindMountPurge.protectedComposePaths(fileURLs: [composeYAML])
        )
        expect(result.removed.count == 1, "integration removes bind-mount directory")
        expect(!FileManager.default.fileExists(atPath: dataDirectory.path), "data directory removed")
        expect(FileManager.default.fileExists(atPath: composeYAML.path), "compose file protected")
    }

    mutating func runVolumePurgeSymlinkEscapeTests() throws {
        let escapeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("compose-verify-volumes-escape-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: escapeRoot) }
        try FileManager.default.createDirectory(at: escapeRoot, withIntermediateDirectories: true)
        let escapeData = escapeRoot.appendingPathComponent("data")
        try FileManager.default.createDirectory(at: escapeData, withIntermediateDirectories: true)
        let allowedPath = escapeData.standardizedFileURL.path
        try FileManager.default.removeItem(at: escapeData)
        try FileManager.default.createSymbolicLink(
            at: escapeData,
            withDestinationURL: escapeRoot.deletingLastPathComponent()
        )
        let escapeResult = BindMountPurge.purge(
            paths: [allowedPath],
            composeDirectory: escapeRoot
        )
        expect(escapeResult.removed.isEmpty, "symlink escape path not removed")
        expect(
            escapeResult.skipped.contains { $0.reason == .outsideComposeRoot },
            "symlink escape skipped with reason"
        )
    }
}
