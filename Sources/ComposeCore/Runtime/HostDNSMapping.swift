import Foundation

/// Installs and removes macOS `/etc/hosts` mappings for `x-compose.hosts`.
package enum HostDNSMapping {
    package struct OwnershipRecord: Codable, Sendable, Equatable {
        package let projectName: String
        package let projectID: String
        package let composeFilePath: String
        package let hostnames: [String]
        package let installedAt: String
    }

    package static func installAll(
        composeFile: ComposeFile,
        projectName: String,
        firstComposeFileURL: URL,
        activeServiceNames: Set<String>,
        dryRunManifest: DryRunManifest? = nil
    ) async throws {
        try validateHostDNSPlatform()
        let identity = HostDNSPlanning.blockIdentity(
            projectName: projectName,
            firstComposeFileURL: firstComposeFileURL
        )
        let devWarnings = try HostDNSPlanning.validateForInstall(
            composeFile: composeFile,
            activeServiceNames: activeServiceNames
        )
        for warning in devWarnings {
            fputs("\(warning.message)\n", stderr)
        }
        let planned = HostDNSPlanning.plans(
            composeFile: composeFile,
            activeServiceNames: activeServiceNames
        )
        guard !planned.isEmpty else {
            fputs("No x-compose.hosts declared; skipping host DNS.\n", stderr)
            return
        }
        if let dryRunManifest {
            await dryRunManifest.recordHostDNSInstall(
                projectName: identity.projectName,
                projectID: identity.projectID,
                hostnames: planned.map(\.hostname)
            )
            return
        }

        try installLive(identity: identity, planned: planned)
    }

    package static func removeProjectMappings(
        projectName: String,
        firstComposeFileURL: URL?,
        dryRunManifest: DryRunManifest? = nil
    ) async {
        guard let identity = resolveIdentity(
            projectName: projectName,
            firstComposeFileURL: firstComposeFileURL
        ) else {
            return
        }

        if let dryRunManifest {
            await dryRunManifest.recordHostDNSRemove(
                projectName: identity.projectName,
                projectID: identity.projectID
            )
            return
        }

        removeLive(identity: identity, projectName: projectName)
    }

    package static func ownershipURL(projectName: String) -> URL {
        ComposeFileStaging.projectRoot(projectName: projectName)
            .appendingPathComponent("host-dns.json")
    }

    package static func writeOwnership(
        identity: HostDNSPlanning.BlockIdentity,
        hostnames: [String]
    ) throws {
        let record = OwnershipRecord(
            projectName: identity.projectName,
            projectID: identity.projectID,
            composeFilePath: identity.composeFilePath,
            hostnames: hostnames.map { HostDNSPlanning.normalizedHostname($0) }.sorted(),
            installedAt: ISO8601DateFormatter().string(from: Date())
        )
        let url = ownershipURL(projectName: identity.projectName)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: 0o700)]
        )
        let data = try JSONEncoder().encode(record)
        try data.write(to: url, options: .atomic)
    }

    package static func readOwnership(projectName: String) -> OwnershipRecord? {
        let url = ownershipURL(projectName: projectName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(OwnershipRecord.self, from: data)
    }

    package static func removeOwnership(projectName: String) {
        try? FileManager.default.removeItem(at: ownershipURL(projectName: projectName))
    }

    package static func warnSameNameDifferentID(
        content: String,
        identity: HostDNSPlanning.BlockIdentity
    ) {
        let others = HostsFileEditor.blocksWithSameProjectName(
            content: content,
            projectName: identity.projectName,
            excludingProjectID: identity.projectID
        )
        guard !others.isEmpty else { return }
        let ids = others.map(\.projectID).joined(separator: ", ")
        fputs(
            """
            Warning: another container-compose block exists for project '\(identity.projectName)' \
            with a different id (\(ids)); manual cleanup of the older block may be needed.\n
            """,
            stderr
        )
    }

    package static func warnRemovalFailed(
        identity: HostDNSPlanning.BlockIdentity,
        reason: String,
        manualCommand: String? = nil
    ) {
        let ownershipPath = ownershipURL(projectName: identity.projectName).path
        var message = """
            Warning: couldn't remove host DNS mappings (\(reason)).
            Remove this block from /etc/hosts manually:
              \(identity.beginMarker)
              \(HostsFileEditor.loopbackIP) …
              \(identity.endMarker)
            Or run: container compose down (accept the prompt when asked for /etc/hosts access)
            Ownership: \(ownershipPath)
            """
        if let manualCommand {
            message += "\nManual command: \(manualCommand)"
        }
        fputs("\(message)\n", stderr)
    }

    private static func validateHostDNSPlatform() throws {
        #if !os(macOS)
        throw ComposeError.hostDNSUnsupportedPlatform
        #endif
    }
}
