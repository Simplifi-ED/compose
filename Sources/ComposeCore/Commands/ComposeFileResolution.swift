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

    package static func resolvedIfPresent(files: [String]) throws -> [URL]? {
        guard !files.isEmpty else { return nil }

        let usingDefaultOnly = files.count == 1 && files[0] == defaultFileName
        var resolved: [URL] = []
        resolved.reserveCapacity(files.count)

        for file in files {
            guard let url = try resolvedIfPresent(file: file) else {
                if usingDefaultOnly { return nil }
                throw ComposeError.fileNotFound(standardizedURL(for: file).path)
            }
            resolved.append(url)
        }

        return resolved
    }

    package static func resolved(files: [String]) throws -> [URL] {
        guard let urls = try resolvedIfPresent(files: files) else {
            throw ComposeError.fileNotFound(standardizedURL(for: defaultFileName).path)
        }
        return urls
    }
}
