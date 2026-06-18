import ArgumentParser
import Foundation

extension Up {
    func installHostDNSIfRequested(_ input: LiveInput) async throws {
        guard input.installHostDNS else { return }
        do {
            try await HostDNSMapping.installLoopbackMappings(
                composeFile: input.plan.composeFile,
                projectName: input.plan.projectName,
                firstComposeFileURL: input.plan.fileURLs[0],
                activeServiceNames: Set(input.plan.plans.map(\.serviceName))
            )
        } catch let error as ComposeError {
            switch error {
            case .hostDNSElevationCancelled:
                fputs(
                    """
                    Warning: Host DNS install cancelled. Containers will start without host mappings.\n
                    """,
                    stderr
                )
            default:
                throw error
            }
        }
    }

    func refreshBridgeHostDNSIfRequested(
        _ input: LiveInput,
        machineContext: MachineContext
    ) async {
        guard input.installHostDNS else { return }
        let activeServiceNames = Set(input.plan.plans.map(\.serviceName))
        guard HostDNSPlanning.hasBridgeHostDeclarations(
            composeFile: input.plan.composeFile,
            activeServiceNames: activeServiceNames
        ) else { return }
        let serviceAddresses = await ContainerNetworkDiscovery.resolveBridgeServiceIPv4Addresses(
            projectName: input.plan.projectName,
            composeFile: input.plan.composeFile
        ) {
            try await ContainerDiscovery.projectContainers(
                forProject: input.plan.projectName,
                machineContext: machineContext
            )
        }
        warnMissingBridgeHostDNSAddresses(
            composeFile: input.plan.composeFile,
            activeServiceNames: activeServiceNames,
            serviceAddresses: serviceAddresses
        )
        guard !serviceAddresses.isEmpty else { return }
        await applyBridgeHostDNSRefresh(
            input: input,
            activeServiceNames: activeServiceNames,
            serviceAddresses: serviceAddresses
        )
    }

    private func warnMissingBridgeHostDNSAddresses(
        composeFile: ComposeFile,
        activeServiceNames: Set<String>,
        serviceAddresses: [String: String]
    ) {
        let bridgeServices = activeServiceNames.filter { serviceName in
            guard let service = composeFile.services[serviceName], !service.hostnames.isEmpty else {
                return false
            }
            return NetworkPlanning.serviceUsesBridgeNetwork(composeFile: composeFile, service: service)
        }
        let missingAddresses = bridgeServices.filter { serviceAddresses[$0] == nil }
        guard !missingAddresses.isEmpty else { return }
        fputs(
            "Warning: Bridge host DNS skipped for service(s) without resolved addresses: "
                + "\(missingAddresses.sorted().joined(separator: ", "))\n",
            stderr
        )
    }

    private func applyBridgeHostDNSRefresh(
        input: LiveInput,
        activeServiceNames: Set<String>,
        serviceAddresses: [String: String]
    ) async {
        do {
            try await HostDNSMapping.refreshBridgeMappings(
                composeFile: input.plan.composeFile,
                projectName: input.plan.projectName,
                firstComposeFileURL: input.plan.fileURLs[0],
                activeServiceNames: activeServiceNames,
                serviceAddresses: serviceAddresses
            )
        } catch let error as ComposeError {
            switch error {
            case .hostDNSElevationCancelled:
                fputs(
                    "Warning: Bridge host DNS refresh cancelled; loopback mappings may still be installed.\n",
                    stderr
                )
            default:
                fputs(
                    "Warning: Bridge host DNS refresh failed: \(error.localizedDescription)\n",
                    stderr
                )
            }
        } catch {
            fputs(
                "Warning: Bridge host DNS refresh failed: \(error.localizedDescription)\n",
                stderr
            )
        }
    }

    func rollbackHostDNSIfNeeded(_ input: LiveInput, unless error: Error) async {
        guard input.installHostDNS else { return }
        if error is ExitCode { return }
        await HostDNSMapping.removeProjectMappings(
            projectName: input.plan.projectName,
            firstComposeFileURL: input.plan.fileURLs[0]
        )
    }
}
