import Foundation

package enum ArchiveExport {
    package struct Plan: Sendable {
        package let projectName: String
        package let composeYAML: String
        package let imageEntries: [ComposeArchiveManifest.ImageMapping]

        package var uniqueReferences: [String] {
            Array(Set(imageEntries.map(\.reference))).sorted()
        }
    }

    package struct LoadResult: Sendable {
        package let manifest: ComposeArchiveManifest
        package let composeYAML: String
        package let loadedReferences: [String]
    }

    package static func plan(
        fileURLs: [URL],
        projectName: String,
        activeProfiles: Set<String>,
        scaleOverrides: [String: Int],
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> Plan {
        let composeFile = try ComposeConfigResolver.resolve(
            fileURLs: fileURLs,
            projectName: projectName,
            activeProfiles: activeProfiles,
            scaleOverrides: scaleOverrides,
            processEnvironment: processEnvironment
        )
        let yaml = try ComposeSerializer.yamlString(from: composeFile)
        let imageEntries = try composeFile.services.keys.sorted().map { serviceName in
            let service = composeFile.services[serviceName]!
            let reference = try BuildImageResolver.resolvedImageTag(
                projectName: projectName,
                serviceName: serviceName,
                service: service
            )
            return ComposeArchiveManifest.ImageMapping(
                service: serviceName,
                reference: reference
            )
        }
        return Plan(
            projectName: projectName,
            composeYAML: yaml,
            imageEntries: imageEntries
        )
    }

    package static func save(
        plan: Plan,
        outputURL: URL
    ) async throws {
        guard !plan.imageEntries.isEmpty else {
            throw ComposeError.noServices
        }
        try await preflightImages(entries: plan.imageEntries)

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("compose-save-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let imagesTarURL = tempDir.appendingPathComponent(ComposeArchiveFormat.imagesTarPath)
        try await saveImages(references: plan.uniqueReferences, outputURL: imagesTarURL)

        let manifest = ComposeArchiveManifest(
            projectName: plan.projectName,
            savedAt: ComposeArchiveManifestFormatting.savedAtTimestamp(),
            images: plan.imageEntries
        )
        let manifestData = try manifest.encodedJSON()
        let composeData = Data(plan.composeYAML.utf8)

        let stagingURL = outputURL.deletingLastPathComponent()
            .appendingPathComponent(".compose-save-\(UUID().uuidString).tar")
        defer { try? FileManager.default.removeItem(at: stagingURL) }

        try writeStackArchive(
            manifestData: manifestData,
            composeData: composeData,
            imagesTarURL: imagesTarURL,
            outputURL: stagingURL
        )

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        try FileManager.default.moveItem(at: stagingURL, to: outputURL)
    }

    package static func load(
        inputURL: URL,
        force: Bool
    ) async throws -> LoadResult {
        let extracted = try extractStackArchive(from: inputURL)
        try ComposeArchiveManifest.validate(extracted.manifest)

        let loadedReferences = try await loadImages(
            inputURL: extracted.imagesTarURL,
            force: force
        )

        return LoadResult(
            manifest: extracted.manifest,
            composeYAML: extracted.composeYAML,
            loadedReferences: loadedReferences
        )
    }
}
