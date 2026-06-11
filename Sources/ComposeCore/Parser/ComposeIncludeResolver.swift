import Foundation
import Yams

enum ComposeIncludeResolver {
    /// `hostFileURL` resolves `include.path` entries; `localProjectDirectory` stamps local services
    /// (include `project_directory` when loaded via an include entry, else the host file's directory).
    static func expand(
        document: ComposeFileDocument,
        hostFileURL: URL,
        localProjectDirectory: URL,
        processEnvironment: [String: String],
        activeChain: [URL] = []
    ) throws -> ComposeFile {
        var model = ComposeFile(
            name: document.name,
            services: stampServices(document.services, projectDirectory: localProjectDirectory)
        )

        let hostDirectory = hostFileURL.deletingLastPathComponent().standardizedFileURL
        let chain = activeChain + [canonicalFileURL(hostFileURL)]
        for entry in document.include {
            let includeLabel = entry.paths.joined(separator: ", ")
            let included = try loadIncludeEntry(
                entry,
                hostDirectory: hostDirectory,
                processEnvironment: processEnvironment,
                activeChain: chain
            )
            try mergeIncludedRejectingConflicts(
                into: &model,
                included: included,
                includePath: includeLabel,
                definedIn: hostFileURL.path
            )
        }

        return model
    }

    static func decodeDocument(
        fileURL: URL,
        includeEntry: ComposeIncludeEntry?,
        hostDirectory: URL,
        processEnvironment: [String: String]
    ) throws -> ComposeFileDocument {
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

        let variables: [String: String]
        if let includeEntry {
            let projectDirectory = resolveProjectDirectory(
                entry: includeEntry,
                hostDirectory: hostDirectory,
                includedFileURL: fileURL
            )
            let envFiles = try resolveEnvFileURLs(
                entry: includeEntry,
                hostDirectory: hostDirectory,
                projectDirectory: projectDirectory
            )
            variables = try ComposeSubstitution.resolveVariables(
                envFiles: envFiles,
                processEnvironment: processEnvironment
            )
        } else {
            variables = try ComposeSubstitution.resolveVariables(
                beside: fileURL,
                processEnvironment: processEnvironment
            )
        }

        let hydrated = try ComposeSubstitution.substitute(contents, variables: variables, composePath: path)

        do {
            return try YAMLDecoder().decode(ComposeFileDocument.self, from: hydrated)
        } catch {
            if let composeError = ComposeParser.extractComposeError(from: error) {
                throw composeError
            }
            throw ComposeError.parseFailed(path, underlying: error)
        }
    }

    private static func loadIncludeEntry(
        _ entry: ComposeIncludeEntry,
        hostDirectory: URL,
        processEnvironment: [String: String],
        activeChain: [URL]
    ) throws -> ComposeFile {
        var mergedModels: [ComposeFile] = []
        for path in entry.paths {
            let fileURL = resolveIncludePath(path, relativeTo: hostDirectory)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw ComposeError.fileNotFound(fileURL.path)
            }
            let chain = activeChain.map { canonicalFileURL($0) }
            if chain.contains(fileURL) {
                throw ComposeError.circularInclude(chain: chain.map(\.path) + [fileURL.path])
            }

            let document = try decodeDocument(
                fileURL: fileURL,
                includeEntry: entry,
                hostDirectory: hostDirectory,
                processEnvironment: processEnvironment
            )
            let projectDirectory = resolveProjectDirectory(
                entry: entry,
                hostDirectory: hostDirectory,
                includedFileURL: fileURL
            )
            let expanded = try expand(
                document: document,
                hostFileURL: fileURL,
                localProjectDirectory: projectDirectory,
                processEnvironment: processEnvironment,
                activeChain: activeChain
            )
            mergedModels.append(expanded)
        }

        guard !mergedModels.isEmpty else {
            throw ComposeError.invalidInclude(reason: "path must list at least one compose file")
        }
        // Multi-path include entry: later paths override earlier ones (same as `-f` merge).
        return ComposeFileMerge.merge(mergedModels)
    }

    /// Adds included services; errors on duplicate names (unlike `ComposeFileMerge`, which overrides).
    private static func mergeIncludedRejectingConflicts(
        into model: inout ComposeFile,
        included: ComposeFile,
        includePath: String,
        definedIn: String
    ) throws {
        var services = model.services
        for (serviceName, service) in included.services {
            if services[serviceName] != nil {
                throw ComposeError.includeConflict(
                    service: serviceName,
                    includePath: includePath,
                    definedIn: definedIn
                )
            }
            services[serviceName] = service
        }
        model = ComposeFile(name: model.name, services: services)
    }

    private static func stampServices(
        _ services: [String: ComposeService],
        projectDirectory: URL
    ) -> [String: ComposeService] {
        services.mapValues { $0.withProjectDirectory(projectDirectory) }
    }

    private static func resolveIncludePath(_ path: String, relativeTo hostDirectory: URL) -> URL {
        URL(fileURLWithPath: path, relativeTo: hostDirectory).standardizedFileURL
    }

    private static func canonicalFileURL(_ url: URL) -> URL {
        url.standardizedFileURL
    }

    private static func resolveProjectDirectory(
        entry: ComposeIncludeEntry,
        hostDirectory: URL,
        includedFileURL: URL
    ) -> URL {
        if let projectDirectory = entry.projectDirectory {
            return URL(fileURLWithPath: projectDirectory, relativeTo: hostDirectory).standardizedFileURL
        }
        if entry.usesShortSyntax {
            return hostDirectory
        }
        return includedFileURL.deletingLastPathComponent().standardizedFileURL
    }

    private static func resolveEnvFileURLs(
        entry: ComposeIncludeEntry,
        hostDirectory: URL,
        projectDirectory: URL
    ) throws -> [URL] {
        if let envFiles = entry.envFile {
            return envFiles.map { path in
                URL(fileURLWithPath: path, relativeTo: hostDirectory).standardizedFileURL
            }
        }

        let defaultEnv = projectDirectory.appendingPathComponent(".env")
        if FileManager.default.fileExists(atPath: defaultEnv.path) {
            return [defaultEnv]
        }
        return []
    }
}
