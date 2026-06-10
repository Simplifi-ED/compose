import Foundation

package enum ComposeFileResolution {
    package static let defaultFileName = "docker-compose.yml"

    private static let discoveryCandidates = [
        "compose.yaml",
        "compose.yml",
        "docker-compose.yaml",
        "docker-compose.yml"
    ]

    package static func discover(
        cliFiles: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> [String] {
        if !cliFiles.isEmpty {
            return cliFiles
        }

        if let composeFile = environment["COMPOSE_FILE"], !composeFile.isEmpty {
            let segments = composeFile.split(separator: ":", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            for segment in segments where segment.isEmpty {
                throw ComposeError.invalidComposeFilePath("COMPOSE_FILE contains an empty path segment")
            }
            let nonEmpty = segments.filter { !$0.isEmpty }
            guard !nonEmpty.isEmpty else {
                throw ComposeError.invalidComposeFilePath("COMPOSE_FILE is empty")
            }
            return nonEmpty
        }

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for candidate in discoveryCandidates {
            let baseURL = cwd.appendingPathComponent(candidate)
            if isRegularFile(at: baseURL.path) {
                var files = [candidate]
                let overrideName = overrideFileName(for: candidate)
                let overrideURL = cwd.appendingPathComponent(overrideName)
                if isRegularFile(at: overrideURL.path) {
                    files.append(overrideName)
                }
                return files
            }
        }

        return [defaultFileName]
    }

    package static func standardizedURL(for file: String) -> URL {
        URL(fileURLWithPath: file, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            .standardizedFileURL
    }

    package static func resolvedIfPresent(file: String) throws -> URL? {
        let url = standardizedURL(for: file)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            if file == defaultFileName { return nil }
            throw ComposeError.fileNotFound(url.path)
        }
        guard !isDirectory.boolValue else {
            throw ComposeError.invalidComposeFilePath(url.path)
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

    private static func overrideFileName(for base: String) -> String {
        if base.hasSuffix(".yaml") {
            return String(base.dropLast(5)) + ".override.yaml"
        }
        if base.hasSuffix(".yml") {
            return String(base.dropLast(4)) + ".override.yml"
        }
        return base + ".override"
    }

    private static func isRegularFile(at path: String) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return false
        }
        return !isDirectory.boolValue
    }
}
