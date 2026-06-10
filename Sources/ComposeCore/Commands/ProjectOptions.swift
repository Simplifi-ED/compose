import ArgumentParser
import Foundation

public struct ProjectOptions: ParsableArguments {
    public init() {}

    @Option(
        name: .shortAndLong,
        help: "Path to a compose file. Repeat to merge; later files override earlier ones."
    )
    var files: [String] = []

    @Option(name: .shortAndLong, help: "Project name used for container naming.")
    var projectName: String?

    var hasExplicitProjectName: Bool {
        guard let projectName else { return false }
        return !projectName.isEmpty
    }

    var effectiveFiles: [String] {
        files.isEmpty ? [ComposeFileResolution.defaultFileName] : files
    }

    func resolvedFileURLs() throws -> [URL] {
        try ComposeFileResolution.resolved(files: effectiveFiles)
    }

    /// Returns compose files when they exist. When only the default filename is requested and absent,
    /// returns nil so `down -p` can tear down by project name alone. Any other missing path throws.
    func resolvedFileURLsIfPresent() throws -> [URL]? {
        try ComposeFileResolution.resolvedIfPresent(files: effectiveFiles)
    }

    func resolvedProjectName(fileURL: URL? = nil) throws -> String {
        if let projectName, !projectName.isEmpty {
            return projectName
        }
        let resolvedURL: URL
        if let fileURL {
            resolvedURL = fileURL
        } else {
            resolvedURL = try resolvedFileURLs()[0]
        }
        let directoryName = resolvedURL.deletingLastPathComponent().lastPathComponent
        if directoryName.isEmpty || directoryName == "/" {
            return "default"
        }
        return directoryName
    }
}
