import ContainerAPIClient
import ContainerCommands
import ContainerizationError
import Foundation

extension ArchiveExport {
    static func preflightImages(
        entries: [ComposeArchiveManifest.ImageMapping]
    ) async throws {
        let containerSystemConfig = try await Application.loadContainerSystemConfig()
        let uniqueReferences = Set(entries.map(\.reference))
        try await withThrowingTaskGroup(of: Void.self) { group in
            for reference in uniqueReferences.sorted() {
                group.addTask {
                    do {
                        _ = try await ClientImage.get(
                            reference: reference,
                            containerSystemConfig: containerSystemConfig
                        )
                    } catch let error as ContainerizationError where error.isCode(.notFound) {
                        let service = entries.first { $0.reference == reference }?.service ?? reference
                        throw ComposeError.imageNotFoundLocally(service: service, reference: reference)
                    }
                }
            }
            try await group.waitForAll()
        }
    }

    static func saveImages(
        references: [String],
        outputURL: URL
    ) async throws {
        var arguments = ["-o", outputURL.path]
        arguments.append(contentsOf: references)
        do {
            let command = try Application.ImageSave.parse(arguments)
            try await command.run()
        } catch {
            throw ComposeError.archiveWriteFailed(path: outputURL.path, underlying: error)
        }
    }

    static func loadImages(
        inputURL: URL,
        force: Bool
    ) async throws -> [String] {
        do {
            let result = try await ClientImage.load(from: inputURL.path, force: force)
            for image in result.images {
                try await image.unpack(platform: nil)
            }
            return result.images.map(\.reference).sorted()
        } catch {
            throw ComposeError.archiveReadFailed(path: inputURL.path, underlying: error)
        }
    }
}
