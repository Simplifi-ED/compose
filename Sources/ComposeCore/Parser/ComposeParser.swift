import Foundation

public enum ComposeParser {
    public static func parse(
        fileURL: URL,
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> ComposeFile {
        try parse(fileURLs: [fileURL], processEnvironment: processEnvironment)
    }

    public static func parse(
        fileURLs: [URL],
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> ComposeFile {
        let composeFile = try decodeMerged(fileURLs: fileURLs, processEnvironment: processEnvironment)
        try validate(composeFile)
        return composeFile
    }

    /// Decode and validate dependency graph only — for `down` when the file may be edited after `up`.
    public static func parseForShutdown(
        fileURL: URL,
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> ComposeFile {
        try parseForShutdown(fileURLs: [fileURL], processEnvironment: processEnvironment)
    }

    public static func parseForShutdown(
        fileURLs: [URL],
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> ComposeFile {
        let composeFile = try decodeMerged(fileURLs: fileURLs, processEnvironment: processEnvironment)
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

    static func decodeMerged(
        fileURLs: [URL],
        processEnvironment: [String: String]
    ) throws -> ComposeFile {
        guard !fileURLs.isEmpty else {
            throw ComposeError.noServices
        }

        let decoded = try fileURLs.map { try decode(fileURL: $0, processEnvironment: processEnvironment) }
        return ComposeFileMerge.merge(decoded)
    }

    static func decode(
        fileURL: URL,
        processEnvironment: [String: String]
    ) throws -> ComposeFile {
        let hostDirectory = fileURL.deletingLastPathComponent().standardizedFileURL
        let document = try ComposeIncludeResolver.decodeDocument(
            fileURL: fileURL,
            includeEntry: nil,
            hostDirectory: hostDirectory,
            processEnvironment: processEnvironment
        )
        return try ComposeIncludeResolver.expand(
            document: document,
            hostFileURL: fileURL,
            localProjectDirectory: hostDirectory,
            processEnvironment: processEnvironment
        )
    }

    static func validate(_ composeFile: ComposeFile) throws {
        guard !composeFile.services.isEmpty else {
            throw ComposeError.noServices
        }

        for (serviceName, service) in composeFile.services {
            let hasImage = service.image.map { !$0.isEmpty } ?? false
            let hasBuild = service.build != nil
            guard hasImage || hasBuild else {
                throw ComposeError.missingImage(service: serviceName)
            }
        }

        try validateShutdownGraph(composeFile)
        try DependencyValidation.validate(services: composeFile.services)
    }

    static func validateShutdownGraph(_ composeFile: ComposeFile) throws {
        guard !composeFile.services.isEmpty else {
            throw ComposeError.noServices
        }

        _ = try DependencyGraph.serviceLayers(for: composeFile.services)
    }
}
