import Foundation

extension HostDNSMapping {
    /// Single post-startup install for loopback and bridged host DNS (live or dry-run).
    package static func installAfterStartup(
        composeFile: ComposeFile,
        projectName: String,
        firstComposeFileURL: URL,
        activeServiceNames: Set<String>,
        dryRunManifest: DryRunManifest? = nil,
        listContainers: (@Sendable () async throws -> [ProjectContainer])? = nil
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

        let serviceAddresses = await resolveServiceAddresses(
            composeFile: composeFile,
            projectName: projectName,
            activeServiceNames: activeServiceNames,
            dryRunManifest: dryRunManifest,
            listContainers: listContainers
        )
        let planned = HostDNSPlanning.plans(
            composeFile: composeFile,
            activeServiceNames: activeServiceNames,
            serviceAddresses: serviceAddresses
        )
        guard !planned.isEmpty else {
            if !hasAnyHostDeclarations(composeFile: composeFile, activeServiceNames: activeServiceNames) {
                fputs("No x-compose.hosts declared; skipping host DNS.\n", stderr)
            }
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

    private static let dryRunBridgePlaceholderIP = "0.0.0.0"

    private static func resolveServiceAddresses(
        composeFile: ComposeFile,
        projectName: String,
        activeServiceNames: Set<String>,
        dryRunManifest: DryRunManifest?,
        listContainers: (@Sendable () async throws -> [ProjectContainer])?
    ) async -> [String: String] {
        let bridgeServices = HostDNSPlanning.bridgeHostServices(
            composeFile: composeFile,
            activeServiceNames: activeServiceNames
        )
        guard !bridgeServices.isEmpty else { return [:] }

        if dryRunManifest != nil {
            return Dictionary(uniqueKeysWithValues: bridgeServices.map { ($0, dryRunBridgePlaceholderIP) })
        }
        guard let listContainers else { return [:] }

        let serviceAddresses = await ContainerNetworkDiscovery.resolveBridgeServiceIPv4Addresses(
            projectName: projectName,
            composeFile: composeFile,
            expectedBridgeServices: bridgeServices,
            listContainers: listContainers
        )
        warnMissingBridgeAddresses(
            bridgeServices: bridgeServices,
            serviceAddresses: serviceAddresses
        )
        return serviceAddresses
    }

    private static func warnMissingBridgeAddresses(
        bridgeServices: Set<String>,
        serviceAddresses: [String: String]
    ) {
        let missing = bridgeServices.filter { serviceAddresses[$0] == nil }.sorted()
        guard !missing.isEmpty else { return }
        fputs(
            "Warning: Bridge host DNS skipped for service(s) without resolved addresses: "
                + "\(missing.joined(separator: ", "))\n",
            stderr
        )
    }

    private static func hasAnyHostDeclarations(
        composeFile: ComposeFile,
        activeServiceNames: Set<String>
    ) -> Bool {
        activeServiceNames.contains { serviceName in
            !(composeFile.services[serviceName]?.hostnames.isEmpty ?? true)
        }
    }
}
