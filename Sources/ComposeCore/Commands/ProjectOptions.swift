import ArgumentParser
import Foundation

public struct ProjectOptions: ParsableArguments {
    public init() {}
    @Option(name: .shortAndLong, help: "Path to the compose file.")
    var file: String = "docker-compose.yml"

    @Option(name: .shortAndLong, help: "Project name used for container naming.")
    var projectName: String?

    func resolvedFileURL() throws -> URL {
        let url = URL(fileURLWithPath: file, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            .standardizedFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ComposeError.fileNotFound(url.path)
        }
        return url
    }

    func resolvedProjectName(fileURL: URL) -> String {
        if let projectName, !projectName.isEmpty {
            return projectName
        }
        let directoryName = fileURL.deletingLastPathComponent().lastPathComponent
        if directoryName.isEmpty || directoryName == "/" {
            return "default"
        }
        return directoryName
    }

    func resolvedProjectName() throws -> String {
        if let projectName, !projectName.isEmpty {
            return projectName
        }
        let fileURL = try resolvedFileURL()
        return resolvedProjectName(fileURL: fileURL)
    }
}
