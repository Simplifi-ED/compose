import Foundation
import Yams

public enum ComposeParser {
    public static func parse(fileURL: URL) throws -> ComposeFile {
        try parse(fileURLs: [fileURL])
    }

    public static func parse(fileURLs: [URL]) throws -> ComposeFile {
        let composeFile = try decodeMerged(fileURLs: fileURLs)
        try validate(composeFile)
        return composeFile
    }

    /// Decode and validate dependency graph only — for `down` when the file may be edited after `up`.
    public static func parseForShutdown(fileURL: URL) throws -> ComposeFile {
        try parseForShutdown(fileURLs: [fileURL])
    }

    public static func parseForShutdown(fileURLs: [URL]) throws -> ComposeFile {
        let composeFile = try decodeMerged(fileURLs: fileURLs)
        try validateShutdownGraph(composeFile)
        return composeFile
    }

    /// Yams wraps `ComposeError` thrown from `Decodable` in `DecodingError.dataCorrupted`.
    static func extractComposeError(from error: Error) -> ComposeError? {
        if let composeError = error as? ComposeError {
            return composeError
        }
        if case DecodingError.dataCorrupted(let context) = error,
           let underlying = context.underlyingError {
            return extractComposeError(from: underlying)
        }
        return nil
    }

    static func decodeMerged(fileURLs: [URL]) throws -> ComposeFile {
        guard !fileURLs.isEmpty else {
            throw ComposeError.noServices
        }

        let decoded = try fileURLs.map { try decode(fileURL: $0) }
        return ComposeFileMerge.merge(decoded)
    }

    static func decode(fileURL: URL) throws -> ComposeFile {
        let path = fileURL.path
        guard FileManager.default.fileExists(atPath: path) else {
            throw ComposeError.fileNotFound(path)
        }

        let contents: String
        do {
            contents = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            throw ComposeError.readFailed(path, underlying: error)
        }

        let variables = try DotEnv.loadVariables(beside: fileURL)
        let hydrated = try DotEnv.substitute(contents, variables: variables, composePath: path)

        do {
            return try YAMLDecoder().decode(ComposeFile.self, from: hydrated)
        } catch {
            if let composeError = Self.extractComposeError(from: error) {
                throw composeError
            }
            throw ComposeError.parseFailed(path, underlying: error)
        }
    }

    static func validate(_ composeFile: ComposeFile) throws {
        guard !composeFile.services.isEmpty else {
            throw ComposeError.noServices
        }

        for (serviceName, service) in composeFile.services {
            guard let image = service.image, !image.isEmpty else {
                throw ComposeError.missingImage(service: serviceName)
            }
        }

        try validateShutdownGraph(composeFile)
    }

    static func validateShutdownGraph(_ composeFile: ComposeFile) throws {
        guard !composeFile.services.isEmpty else {
            throw ComposeError.noServices
        }

        _ = try DependencyGraph.serviceLayers(for: composeFile.services)
    }
}
