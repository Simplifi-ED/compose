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
    }
}
