import ComposeCore
import Foundation

extension TestRunner {
    mutating func runArchiveTests() throws {
        try runArchivePlanTests()
        try runArchiveManifestTests()
        try runArchiveUnsupportedVersionTests()
        try runArchiveMissingMemberTests()
        try runArchiveRoundTripExtractTests()
        runArchiveDryRunFormattingTests()
        runArchiveErrorMessageTests()
    }

    private mutating func runArchivePlanTests() throws {
        let fixtureURL = Self.fixtureURL("minimal-compose.yml")
        let projectName = "demo"
        let plan = try ArchiveExport.plan(
            fileURLs: [fixtureURL],
            projectName: projectName,
            activeProfiles: [],
            scaleOverrides: [:]
        )
        expect(plan.projectName == projectName, "archive plan project name")
        expect(plan.imageEntries.count == 1, "archive plan service count")
        expect(plan.imageEntries[0].service == "web", "archive plan service name")
        expect(
            plan.imageEntries[0].reference == "docker.io/library/alpine:latest",
            "archive plan resolved image reference"
        )
        expect(plan.uniqueReferences == ["docker.io/library/alpine:latest"], "archive plan unique references")
        expect(plan.composeYAML.contains("services:"), "archive plan compose yaml")

        let buildFixture = Self.fixtureURL("build-compose.yml")
        let buildPlan = try ArchiveExport.plan(
            fileURLs: [buildFixture],
            projectName: "myapp",
            activeProfiles: [],
            scaleOverrides: [:]
        )
        expect(buildPlan.imageEntries[0].reference == "myapp_web", "archive plan build default tag")
    }

    private mutating func runArchiveManifestTests() throws {
        let manifest = ComposeArchiveManifest(
            projectName: "demo",
            savedAt: ComposeArchiveManifestFormatting.savedAtTimestamp(),
            images: [
                ComposeArchiveManifest.ImageMapping(service: "web", reference: "demo_web"),
                ComposeArchiveManifest.ImageMapping(service: "api", reference: "demo_api")
            ]
        )
        expect(manifest.formatVersion == ComposeArchiveFormat.formatVersion, "archive manifest format version")
        expect(manifest.serviceCount == 2, "archive manifest service count")
        expect(manifest.imageCount == 2, "archive manifest image count")

        let data = try manifest.encodedJSON()
        let decoded = try ComposeArchiveManifest.decode(from: data)
        expect(decoded == manifest, "archive manifest encode/decode round-trip")
    }

    private mutating func runArchiveUnsupportedVersionTests() throws {
        let valid = ComposeArchiveManifest(
            projectName: "demo",
            savedAt: "2026-06-12T12:00:00Z",
            images: [ComposeArchiveManifest.ImageMapping(service: "web", reference: "demo_web")]
        )
        expectComposeError(
            "archive unsupported version",
            matching: {
                if case .archiveUnsupportedVersion(let found, let supported) = $0 {
                    found == 99 && supported == ComposeArchiveFormat.formatVersion
                } else {
                    false
                }
            },
            body: {
                let data = try valid.encodedJSON()
                guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw ComposeError.archiveInvalid(reason: "Couldn't parse manifest JSON object.")
                }
                object["formatVersion"] = 99
                let invalidData = try JSONSerialization.data(withJSONObject: object)
                let parsed = try ComposeArchiveManifest.decode(from: invalidData)
                try ComposeArchiveManifest.validate(parsed)
            }
        )
    }

    private mutating func runArchiveMissingMemberTests() throws {
        let manifest = ComposeArchiveManifest(
            projectName: "demo",
            savedAt: "2026-06-12T12:00:00Z",
            images: [ComposeArchiveManifest.ImageMapping(service: "web", reference: "demo_web")]
        )
        let manifestData = try manifest.encodedJSON()
        let composeData = Data("services: {}\n".utf8)
        let imagesTarURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("compose-verify-images-\(UUID().uuidString).tar")

        try runArchiveMissingMemberTest(
            name: "archive missing manifest.json",
            missingPath: ComposeArchiveFormat.manifestPath,
            members: ArchiveExport.CollectedMembers(
                composeData: composeData,
                imagesTarURL: imagesTarURL
            )
        )
        try runArchiveMissingMemberTest(
            name: "archive missing compose.yaml",
            missingPath: ComposeArchiveFormat.composeYAMLPath,
            members: ArchiveExport.CollectedMembers(
                manifestData: manifestData,
                imagesTarURL: imagesTarURL
            )
        )
        try runArchiveMissingMemberTest(
            name: "archive missing images.tar",
            missingPath: ComposeArchiveFormat.imagesTarPath,
            members: ArchiveExport.CollectedMembers(
                manifestData: manifestData,
                composeData: composeData
            )
        )
    }

    private mutating func runArchiveMissingMemberTest(
        name: String,
        missingPath: String,
        members: ArchiveExport.CollectedMembers
    ) throws {
        expectComposeError(
            name,
            matching: {
                if case .archiveInvalid(let reason) = $0 {
                    reason.contains(missingPath)
                } else {
                    false
                }
            },
            body: {
                try ArchiveExport.validateCollectedMembers(members)
            }
        )
    }

    private mutating func runArchiveRoundTripExtractTests() throws {
        let manifest = ComposeArchiveManifest(
            projectName: "demo",
            savedAt: "2026-06-12T12:00:00Z",
            images: [ComposeArchiveManifest.ImageMapping(service: "web", reference: "demo_web")]
        )
        let composeYAML = "services:\n  web:\n    image: demo_web\n"
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("compose-verify-roundtrip-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let imagesTarURL = tempDir.appendingPathComponent("images.tar")
        try Data("fake-oci-tar".utf8).write(to: imagesTarURL)
        let archiveURL = tempDir.appendingPathComponent("stack.tar")
        try ArchiveExport.writeStackArchive(
            manifestData: try manifest.encodedJSON(),
            composeData: Data(composeYAML.utf8),
            imagesTarURL: imagesTarURL,
            outputURL: archiveURL
        )

        let extracted = try ArchiveExport.extractStackArchive(from: archiveURL)
        expect(extracted.manifest == manifest, "archive extract manifest round-trip")
        expect(extracted.composeYAML == composeYAML, "archive extract compose yaml round-trip")
    }

    private mutating func runArchiveDryRunFormattingTests() {
        let imageLine = DryRunManifestFormatting.formatSaveImage(
            service: "web",
            reference: "demo_web"
        )
        expect(
            imageLine == "[DRY-RUN] save image \"demo_web\" service=\"web\"",
            "archive dry-run save image line"
        )

        let archiveLine = DryRunManifestFormatting.formatSaveArchive(
            path: "/tmp/stack.tar",
            imageCount: 2,
            serviceCount: 3
        )
        expect(
            archiveLine == "[DRY-RUN] write archive \"/tmp/stack.tar\" images=2 services=3",
            "archive dry-run write archive line"
        )
    }

    private mutating func runArchiveErrorMessageTests() {
        let error = ComposeError.imageNotFoundLocally(service: "web", reference: "demo_web")
        let message = error.localizedDescription
        expect(message.contains("web"), "archive imageNotFoundLocally mentions service")
        expect(message.contains("demo_web"), "archive imageNotFoundLocally mentions reference")
        expect(message.contains("compose up"), "archive imageNotFoundLocally suggests compose up")
    }
}
