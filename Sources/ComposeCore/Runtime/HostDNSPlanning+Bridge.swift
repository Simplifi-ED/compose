import Foundation

extension HostDNSPlanning {
    package static func plans(
        composeFile: ComposeFile,
        activeServiceNames: Set<String>,
        serviceAddresses: [String: String] = [:]
    ) -> [Plan] {
        var result: [Plan] = []
        for serviceName in activeServiceNames.sorted() {
            guard let service = composeFile.services[serviceName], !service.hostnames.isEmpty else {
                continue
            }
            let onBridge = NetworkPlanning.serviceUsesBridgeNetwork(composeFile: composeFile, service: service)
            let hostPort = firstStaticHostPort(service: service) ?? ""
            let targetIP: String
            if onBridge, let address = serviceAddresses[serviceName] {
                targetIP = address
            } else if onBridge {
                continue
            } else {
                targetIP = Self.targetIP
            }
            if !onBridge, hostPort.isEmpty { continue }
            for hostname in service.hostnames {
                result.append(
                    Plan(
                        serviceName: serviceName,
                        hostname: normalizedHostname(hostname),
                        hostPort: hostPort,
                        targetIP: targetIP
                    )
                )
            }
        }
        return result
    }

    package static func loopbackPlans(
        composeFile: ComposeFile,
        activeServiceNames: Set<String>
    ) -> [Plan] {
        plans(composeFile: composeFile, activeServiceNames: activeServiceNames)
            .filter { plan in
                guard let service = composeFile.services[plan.serviceName] else { return false }
                return !NetworkPlanning.serviceUsesBridgeNetwork(composeFile: composeFile, service: service)
            }
    }

    package static func bridgePlans(
        composeFile: ComposeFile,
        activeServiceNames: Set<String>,
        serviceAddresses: [String: String]
    ) -> [Plan] {
        plans(
            composeFile: composeFile,
            activeServiceNames: activeServiceNames,
            serviceAddresses: serviceAddresses
        )
        .filter { plan in
            guard let service = composeFile.services[plan.serviceName] else { return false }
            return NetworkPlanning.serviceUsesBridgeNetwork(composeFile: composeFile, service: service)
        }
    }

    package static func hasBridgeHostDeclarations(
        composeFile: ComposeFile,
        activeServiceNames: Set<String>
    ) -> Bool {
        activeServiceNames.contains { serviceName in
            guard let service = composeFile.services[serviceName], !service.hostnames.isEmpty else {
                return false
            }
            return NetworkPlanning.serviceUsesBridgeNetwork(composeFile: composeFile, service: service)
        }
    }

    package static func nonDevSuffixBridgeWarning(hostname: String, onBridge: Bool) -> HostDNSWarning? {
        guard !isDevSuffixHostname(hostname) else { return nil }
        let mappingNote = onBridge
            ? "mapping it to a container bridge address affects the whole machine while this project is up."
            : "mapping it to 127.0.0.1 affects the whole machine while this project is up."
        return HostDNSWarning(
            message:
                "Warning: Host '\(hostname)' is not a dev suffix "
                + "(.local, .test, .localhost, .invalid, .example); "
                + "\(mappingNote) "
                + "Prefer .local or .test."
        )
    }
}
