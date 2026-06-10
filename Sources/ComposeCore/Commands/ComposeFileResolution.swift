import Foundation

package enum ComposeFileResolution {
    package static let defaultFileName = "docker-compose.yml"

    package static func standardizedURL(for file: String) -> URL {
        URL(fileURLWithPath: file, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            .standardizedFileURL
    }

    package static func resolvedIfPresent(file: String) throws -> URL? {
        let url = standardizedURL(for: file)
        guard FileManager.default.fileExists(atPath: url.path) else {
            if file == defaultFileName { return nil }
            throw ComposeError.fileNotFound(url.path)
        }
        return url
    }

    package static func resolved(file: String) throws -> URL {
        guard let url = try resolvedIfPresent(file: file) else {
            throw ComposeError.fileNotFound(standardizedURL(for: file).path)
        }
        return url
    }
}
