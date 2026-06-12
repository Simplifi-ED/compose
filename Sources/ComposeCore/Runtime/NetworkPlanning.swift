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

        package init(logicalName: String, runtimeName: String) {
            self.logicalName = logicalName
            self.runtimeName = runtimeName
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

    /// Rejects service memberships that reference networks missing from root `networks:`.
    package static func validate(composeFile: ComposeFile, activeServiceNames: Set<String>) throws {
        for serviceName in activeServiceNames.sorted() {
            guard let service = composeFile.services[serviceName] else { continue }
            for networkName in service.networks where composeFile.networks[networkName] == nil {
                throw ComposeError.undefinedNetwork(service: serviceName, network: networkName)
            }
        }
    }

    /// Unique networks referenced by active services, sorted by logical name.
    ///
    /// Call ``validate(composeFile:activeServiceNames:)`` before planning when
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
                runtimeName: try runtimeNetworkName(projectName: projectName, networkName: logicalName)
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
