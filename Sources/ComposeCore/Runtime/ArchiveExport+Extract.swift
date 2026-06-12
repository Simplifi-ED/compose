import ContainerizationArchive
import Foundation

extension ArchiveExport {
    package struct CollectedMembers: Sendable {
        package var manifestData: Data?
        package var composeData: Data?
        package var imagesTarURL: URL?

        package init(
            manifestData: Data? = nil,
            composeData: Data? = nil,
            imagesTarURL: URL? = nil
        ) {
            self.manifestData = manifestData
            self.composeData = composeData
            self.imagesTarURL = imagesTarURL
        }
    }

    package struct ExtractedStack: Sendable {
        package let manifest: ComposeArchiveManifest
        package let composeYAML: String
        package let imagesTarURL: URL
    }

    package static func validateCollectedMembers(_ collected: CollectedMembers) throws {
        _ = try validatedMembers(from: collected)
    }

    package static func extractStackArchive(from inputURL: URL) throws -> ExtractedStack {
        let extracted = try extractMembers(from: inputURL)
        return ExtractedStack(
            manifest: extracted.manifest,
            composeYAML: extracted.composeYAML,
            imagesTarURL: extracted.imagesTarURL
        )
    }

    private struct ExtractedMembers {
        let manifest: ComposeArchiveManifest
        let composeYAML: String
        let imagesTarURL: URL
    }

    private static func extractMembers(from inputURL: URL) throws -> ExtractedMembers {
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw ComposeError.archiveInvalid(reason: "Archive '\(inputURL.path)' doesn't exist.")
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("compose-load-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let collected = try collectArchiveMembers(from: inputURL, tempDir: tempDir)
        return try validatedMembers(from: collected)
    }

    private static func collectArchiveMembers(
        from inputURL: URL,
        tempDir: URL
    ) throws -> CollectedMembers {
        var collected = CollectedMembers()
        let reader = try ArchiveReader(
            format: .paxRestricted,
            filter: .none,
            file: inputURL
        )
        var streamIterator = reader.makeStreamingIterator()
        while let (entry, streamReader) = streamIterator.next() {
            guard let path = entry.path else {
                try drainStream(streamReader)
                continue
            }
            switch path {
            case ComposeArchiveFormat.manifestPath:
                collected.manifestData = try readStreamData(streamReader)
            case ComposeArchiveFormat.composeYAMLPath:
                collected.composeData = try readStreamData(streamReader)
            case ComposeArchiveFormat.imagesTarPath:
                let destination = tempDir.appendingPathComponent(ComposeArchiveFormat.imagesTarPath)
                try writeStream(streamReader, to: destination)
                collected.imagesTarURL = destination
            default:
                try drainStream(streamReader)
            }
        }
        return collected
    }

    private static func validatedMembers(from collected: CollectedMembers) throws -> ExtractedMembers {
        guard let manifestData = collected.manifestData else {
            throw ComposeError.archiveInvalid(reason: "Missing '\(ComposeArchiveFormat.manifestPath)' member.")
        }
        guard let composeData = collected.composeData else {
            throw ComposeError.archiveInvalid(reason: "Missing '\(ComposeArchiveFormat.composeYAMLPath)' member.")
        }
        guard let composeYAML = String(data: composeData, encoding: .utf8) else {
            throw ComposeError.archiveInvalid(
                reason: "Couldn't decode '\(ComposeArchiveFormat.composeYAMLPath)' as UTF-8 text."
            )
        }
        guard let imagesTarURL = collected.imagesTarURL else {
            throw ComposeError.archiveInvalid(reason: "Missing '\(ComposeArchiveFormat.imagesTarPath)' member.")
        }

        let manifest: ComposeArchiveManifest
        do {
            manifest = try ComposeArchiveManifest.decode(from: manifestData)
        } catch {
            throw ComposeError.archiveInvalid(reason: "Couldn't parse manifest.json.")
        }

        return ExtractedMembers(
            manifest: manifest,
            composeYAML: composeYAML,
            imagesTarURL: imagesTarURL
        )
    }

    private static func readStreamData(_ stream: ArchiveEntryReader) throws -> Data {
        var data = Data()
        let chunkSize = 64 * 1024
        var buffer = [UInt8](repeating: 0, count: chunkSize)
        while true {
            let bytesRead = buffer.withUnsafeMutableBytes { rawBuffer in
                guard let baseAddress = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return 0
                }
                return stream.read(baseAddress, maxLength: chunkSize)
            }
            if bytesRead <= 0 { break }
            data.append(buffer, count: bytesRead)
        }
        return data
    }

    private static func writeStream(_ stream: ArchiveEntryReader, to destination: URL) throws {
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }
        let chunkSize = 4 * 1024 * 1024
        var buffer = [UInt8](repeating: 0, count: chunkSize)
        while true {
            let bytesRead = buffer.withUnsafeMutableBytes { rawBuffer in
                guard let baseAddress = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return 0
                }
                return stream.read(baseAddress, maxLength: chunkSize)
            }
            if bytesRead <= 0 { break }
            handle.write(Data(buffer[0..<bytesRead]))
        }
    }

    private static func drainStream(_ stream: ArchiveEntryReader) throws {
        let chunkSize = 64 * 1024
        var buffer = [UInt8](repeating: 0, count: chunkSize)
        while true {
            let bytesRead = buffer.withUnsafeMutableBytes { rawBuffer in
                guard let baseAddress = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return 0
                }
                return stream.read(baseAddress, maxLength: chunkSize)
            }
            if bytesRead <= 0 { break }
        }
    }
}
