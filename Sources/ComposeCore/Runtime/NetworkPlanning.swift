import Foundation

/// Pure validation and naming for compose networks.
///
/// Network create/delete side effects live in `NetworkRunner`; run-argument
/// emission lives in `ServiceRunMapping`. This module never calls either.
package enum NetworkPlanning {
    package struct Plan: Sendable, Equatable {
        package let logicalName: String
        /// Project-scoped runtime name: `{project}_{logical}`.
        package let runtimeName: String
        package let mode: NetworkAttachmentMode

        package init(logicalName: String, runtimeName: String, mode: NetworkAttachmentMode = .nat) {
            self.logicalName = logicalName
            self.runtimeName = runtimeName
            self.mode = mode
        }
    }

    /// Mirrors upstream `NetworkResource.nameValid` (ContainerResource): lowercase
    /// alphanumerics up to 63 characters; dots, hyphens, underscores interior-only.
    private static let runtimeNamePattern = #"^[a-z0-9](?:[a-z0-9._-]{0,61}[a-z0-9])?$"#

    package static func runtimeNetworkName(projectName: String, networkName: String) throws -> String {
        let runtimeName = "\(projectName)_\(networkName)"
        guard runtimeName.range(of: runtimeNamePattern, options: .regularExpression) != nil else {
            throw ComposeError.invalidNetworkName(network: networkName, runtimeName: runtimeName)
        }
        return runtimeName
    }

    package static func networkMode(
        composeFile: ComposeFile,
        networkName: String
    ) -> NetworkAttachmentMode {
        composeFile.networks[networkName]?.mode ?? .nat
    }

    package static func firstBridgeNetworkName(
        composeFile: ComposeFile,
        service: ComposeService
    ) -> String? {
        service.networks.first { networkMode(composeFile: composeFile, networkName: $0) == .bridge }
    }

    package static func serviceUsesBridgeNetwork(
        composeFile: ComposeFile,
        service: ComposeService
    ) -> Bool {
        service.networks.contains { networkMode(composeFile: composeFile, networkName: $0) == .bridge }
    }

    package static func hasBridgeNetwork(
        composeFile: ComposeFile,
        activeServiceNames: Set<String>
    ) -> Bool {
        var referenced: Set<String> = []
        for serviceName in activeServiceNames {
            guard let service = composeFile.services[serviceName] else { continue }
            referenced.formUnion(service.networks)
        }
        return referenced.contains { networkMode(composeFile: composeFile, networkName: $0) == .bridge }
    }

    /// Rejects service memberships that reference networks missing from root `networks:`.
    package static func validate(
        composeFile: ComposeFile,
        activeServiceNames: Set<String>,
        machineName: String? = nil
    ) throws {
        for serviceName in activeServiceNames.sorted() {
            guard let service = composeFile.services[serviceName] else { continue }
            for networkName in service.networks where composeFile.networks[networkName] == nil {
                throw ComposeError.undefinedNetwork(service: serviceName, network: networkName)
            }
        }
        if machineName != nil, hasBridgeNetwork(composeFile: composeFile, activeServiceNames: activeServiceNames) {
            throw ComposeError.bridgeNetworksUnsupportedWithMachine
        }
        if hasBridgeNetwork(composeFile: composeFile, activeServiceNames: activeServiceNames) {
            guard #available(macOS 26, *) else {
                throw ComposeError.networksRequireMacOS26
            }
        }
    }

    /// Unique networks referenced by active services, sorted by logical name.
    ///
    /// Call ``validate(composeFile:activeServiceNames:machineName:)`` before planning when
    /// undefined memberships must be rejected (for example `up` and `run`).
    package static func plans(
        composeFile: ComposeFile,
        projectName: String,
        activeServiceNames: Set<String>
    ) throws -> [Plan] {
        try validate(composeFile: composeFile, activeServiceNames: activeServiceNames)
        var referenced: Set<String> = []
        for serviceName in activeServiceNames {
            guard let service = composeFile.services[serviceName] else { continue }
            referenced.formUnion(service.networks)
        }
        return try referenced.sorted().map { logicalName in
            Plan(
                logicalName: logicalName,
                runtimeName: try runtimeNetworkName(projectName: projectName, networkName: logicalName),
                mode: networkMode(composeFile: composeFile, networkName: logicalName)
            )
        }
    }

    /// `--network` flags for one service; an empty membership emits nothing
    /// so the runtime attaches the builtin default network.
    package static func networkFlags(service: ComposeService, projectName: String) throws -> [String] {
        try service.networks.flatMap { networkName in
            ["--network", try runtimeNetworkName(projectName: projectName, networkName: networkName)]
        }
    }
}
