import ArgumentParser
import Foundation

public struct ProjectOptions: ParsableArguments {
    public init() {}
    @Option(name: .shortAndLong, help: "Path to the compose file.")
    var file: String = "docker-compose.yml"

    @Option(name: .shortAndLong, help: "Project name used for container naming.")
    var projectName: String?

    func resolvedFileURL() throws -> URL {
        guard let url = resolvedFileURLIfPresent() else {
            let url = URL(fileURLWithPath: file, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
                .standardizedFileURL
            throw ComposeError.fileNotFound(url.path)
        }
        return url
    }

    func resolvedFileURLIfPresent() -> URL? {
        let url = URL(fileURLWithPath: file, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            .standardizedFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return url
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
