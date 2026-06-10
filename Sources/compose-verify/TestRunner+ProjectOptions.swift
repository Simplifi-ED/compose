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

        let defaultFileURL = try ComposeFileResolution.resolvedIfPresent(file: ComposeFileResolution.defaultFileName)
        expect(defaultFileURL == nil, "default compose file optional when absent")

        expectComposeError(
            "explicit missing compose file",
            matching: { if case .fileNotFound = $0 { true } else { false } },
            body: { _ = try ComposeFileResolution.resolvedIfPresent(file: "missing-compose.yml") }
        )
    }
}
