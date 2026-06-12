import Foundation

// Compose stack archive v1 — uncompressed pax-restricted tar members at archive root:
//   manifest.json  — format header + project/image metadata
//   compose.yaml   — fully resolved compose configuration
//   images.tar     — nested OCI tar from `container image save`

package enum ComposeArchiveFormat {
    package static let formatVersion = 1
    package static let manifestPath = "manifest.json"
    package static let composeYAMLPath = "compose.yaml"
    package static let imagesTarPath = "images.tar"
}

package struct ComposeArchiveManifest: Codable, Sendable, Equatable {
    package struct ImageMapping: Codable, Sendable, Equatable {
        package let service: String
        package let reference: String

        package init(service: String, reference: String) {
            self.service = service
            self.reference = reference
        }
    }

    package let formatVersion: Int
    package let projectName: String
    package let savedAt: String
    package let images: [ImageMapping]
    package let serviceCount: Int
    package let imageCount: Int

    package init(
        projectName: String,
        savedAt: String,
        images: [ImageMapping]
    ) {
        self.formatVersion = ComposeArchiveFormat.formatVersion
        self.projectName = projectName
        self.savedAt = savedAt
        self.images = images
        self.serviceCount = images.count
        self.imageCount = Set(images.map(\.reference)).count
    }

    package func encodedJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    package static func decode(from data: Data) throws -> ComposeArchiveManifest {
        try JSONDecoder().decode(ComposeArchiveManifest.self, from: data)
    }

    package static func validate(_ manifest: ComposeArchiveManifest) throws {
        guard manifest.formatVersion == ComposeArchiveFormat.formatVersion else {
            throw ComposeError.archiveUnsupportedVersion(
                found: manifest.formatVersion,
                supported: ComposeArchiveFormat.formatVersion
            )
        }
    }
}

package enum ComposeArchiveManifestFormatting {
    package static func savedAtTimestamp(from date: Date = Date()) -> String {
        date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }
}
