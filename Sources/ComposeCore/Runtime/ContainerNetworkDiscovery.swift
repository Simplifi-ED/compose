import ContainerResource
import ContainerizationExtras
import Foundation

/// Pure helpers for reading container network attachments from runtime snapshots.
package enum ContainerNetworkDiscovery {
    package static let bridgeIPRetryCount = 3
    package static let bridgeIPRetryDelayNanoseconds: UInt64 = 500_000_000

    package static func primaryIPv4HostAddress(from attachments: [Attachment]) -> String? {
        guard let attachment = attachments.first else { return nil }
        return ipv4HostAddress(attachment.ipv4Address)
    }

    package static func primaryIPv4HostAddress(
        from attachments: [Attachment],
        network runtimeName: String
    ) -> String? {
        let attachment = attachments.first(where: { $0.network == runtimeName }) ?? attachments.first
        guard let attachment else { return nil }
        return ipv4HostAddress(attachment.ipv4Address)
    }

    package static func ipv4HostAddress(_ cidr: CIDRv4) -> String {
        cidr.address.description
    }

    package static func resolveServiceIPv4Addresses(
        projectName: String,
        composeFile: ComposeFile,
        containers: [ProjectContainer]
    ) -> [String: String] {
        var result: [String: String] = [:]
        for container in containers {
            guard let serviceName = container.serviceName else { continue }
            guard let address = primaryIPv4HostAddress(
                for: container,
                projectName: projectName,
                composeFile: composeFile
            ) else {
                continue
            }
            result[serviceName] = address
        }
        return result
    }

    package static func primaryIPv4HostAddress(
        for container: ProjectContainer,
        projectName: String,
        composeFile: ComposeFile
    ) -> String? {
        guard let serviceName = container.serviceName,
              let service = composeFile.services[serviceName] else {
            return primaryIPv4HostAddress(from: container.networkAttachments)
        }
        if let bridgeNetwork = NetworkPlanning.firstBridgeNetworkName(
            composeFile: composeFile,
            service: service
        ) {
            let runtimeName = (try? NetworkPlanning.runtimeNetworkName(
                projectName: projectName,
                networkName: bridgeNetwork
            )) ?? bridgeNetwork
            return primaryIPv4HostAddress(from: container.networkAttachments, network: runtimeName)
        }
        if let networkName = service.networks.first {
            let runtimeName = (try? NetworkPlanning.runtimeNetworkName(
                projectName: projectName,
                networkName: networkName
            )) ?? networkName
            return primaryIPv4HostAddress(from: container.networkAttachments, network: runtimeName)
        }
        return primaryIPv4HostAddress(from: container.networkAttachments)
    }

    /// ponytail: fixed 3×500ms retry for bridge DHCP; upgrade path = upstream attach event.
    package static func resolveBridgeServiceIPv4Addresses(
        projectName: String,
        composeFile: ComposeFile,
        expectedBridgeServices: Set<String>,
        listContainers: @Sendable () async throws -> [ProjectContainer]
    ) async -> [String: String] {
        guard !expectedBridgeServices.isEmpty else { return [:] }
        for attempt in 0..<bridgeIPRetryCount {
            let containers = try? await listContainers()
            let addresses = resolveServiceIPv4Addresses(
                projectName: projectName,
                composeFile: composeFile,
                containers: containers ?? []
            )
            let missing = expectedBridgeServices.filter { addresses[$0] == nil }
            if missing.isEmpty || attempt == bridgeIPRetryCount - 1 {
                return addresses.filter { expectedBridgeServices.contains($0.key) }
            }
            try? await Task.sleep(nanoseconds: bridgeIPRetryDelayNanoseconds)
        }
        return [:]
    }
}
