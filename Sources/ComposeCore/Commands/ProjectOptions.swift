import ArgumentParser
import Foundation

public struct ProjectOptions: ParsableArguments {
    public init() {}

    @Option(name: .shortAndLong, help: "Path to the compose file.")
    var file: String = ComposeFileResolution.defaultFileName

    @Option(name: .shortAndLong, help: "Project name used for container naming.")
    var projectName: String?

    var hasExplicitProjectName: Bool {
        guard let projectName else { return false }
        return !projectName.isEmpty
    }

    func resolvedFileURL() throws -> URL {
        try ComposeFileResolution.resolved(file: file)
    }

    /// Returns the compose file when it exists. When the default filename is absent, returns nil so
    /// `down -p` can tear down by project name alone. Any other missing path throws.
    func resolvedFileURLIfPresent() throws -> URL? {
        try ComposeFileResolution.resolvedIfPresent(file: file)
    }

    func resolvedProjectName(fileURL: URL? = nil) throws -> String {
        if let projectName, !projectName.isEmpty {
            return projectName
        }
        let resolvedURL = try fileURL ?? resolvedFileURL()
        let directoryName = resolvedURL.deletingLastPathComponent().lastPathComponent
        if directoryName.isEmpty || directoryName == "/" {
            return "default"
        }
        return directoryName
    }
}
