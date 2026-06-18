import CryptoKit
import Foundation

package struct HostDNSWarning: Sendable, Equatable {
    package let message: String
}

/// Pure validation and planning for macOS host DNS mappings (`x-compose.hosts`).
package enum HostDNSPlanning {
    package static let targetIP = "127.0.0.1"

    package struct Plan: Sendable, Equatable {
        package let serviceName: String
        package let hostname: String
        package let hostPort: String
        package let targetIP: String

        package init(
            serviceName: String,
            hostname: String,
            hostPort: String,
            targetIP: String = HostDNSPlanning.targetIP
        ) {
            self.serviceName = serviceName
            self.hostname = hostname
            self.hostPort = hostPort
            self.targetIP = targetIP
        }
    }

    package struct BlockIdentity: Sendable, Equatable {
        package let projectName: String
        package let projectID: String
        package let composeFilePath: String

        package var beginMarker: String {
            HostsFileEditor.beginMarker(projectName: projectName, projectID: projectID)
        }

        package var endMarker: String {
            HostsFileEditor.endMarker(projectName: projectName, projectID: projectID)
        }
    }

    package static func projectID(firstComposeFileURL: URL, projectName: String) -> String {
        let path = firstComposeFileURL.standardizedFileURL.path
        let material = path + "\0" + projectName
        let digest = SHA256.hash(data: Data(material.utf8))
        // ponytail: 6-byte prefix (~1 in 2^48 collision); upgrade path = full SHA256 hex in marker
        return digest.prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    package static func blockIdentity(
        projectName: String,
        firstComposeFileURL: URL
    ) -> BlockIdentity {
        BlockIdentity(
            projectName: projectName,
            projectID: projectID(firstComposeFileURL: firstComposeFileURL, projectName: projectName),
            composeFilePath: firstComposeFileURL.standardizedFileURL.path
        )
    }

    package static func warnings(
        composeFile: ComposeFile,
        activeServiceNames: Set<String>
    ) -> [HostDNSWarning] {
        collectIssues(composeFile: composeFile, activeServiceNames: activeServiceNames, strict: false).warnings
    }

    package static func validateForInstall(
        composeFile: ComposeFile,
        activeServiceNames: Set<String>
    ) throws -> [HostDNSWarning] {
        let issues = collectIssues(composeFile: composeFile, activeServiceNames: activeServiceNames, strict: true)
        if let error = issues.firstError {
            throw error
        }
        return issues.warnings
    }

    package static func validate(
        composeFile: ComposeFile,
        activeServiceNames: Set<String>,
        strict: Bool
    ) throws {
        let issues = collectIssues(composeFile: composeFile, activeServiceNames: activeServiceNames, strict: strict)
        if let error = issues.firstError {
            throw error
        }
    }

    package static func validateExternalConflicts(
        plans: [Plan],
        hostsContent: String,
        projectID: String? = nil,
        strict: Bool
    ) throws -> [HostDNSWarning] {
        let conflicts = HostsFileEditor.findConflicts(
            in: hostsContent,
            hostnames: plans.map(\.hostname),
            excludingProjectID: projectID
        )
        var warnings: [HostDNSWarning] = []
        for conflict in conflicts {
            switch conflict.kind {
            case .foreignIP(let address, let line):
                let message =
                    "Host '\(conflict.hostname)' already maps to \(address) in /etc/hosts (line \(line))"
                if strict {
                    throw ComposeError.hostDNSExternalConflict(
                        hostname: conflict.hostname,
                        address: address,
                        line: line
                    )
                }
                warnings.append(HostDNSWarning(message: "Warning: \(message)"))
            case .duplicateLoopback(let line):
                warnings.append(
                    HostDNSWarning(
                        message:
                            "Warning: Host '\(conflict.hostname)' already maps to 127.0.0.1 "
                            + "outside container-compose (line \(line)); first match wins on macOS"
                    )
                )
            case .managedByOtherProject(let projectName, let line):
                let message =
                    "Host '\(conflict.hostname)' is already mapped by container-compose project "
                    + "'\(projectName)' (line \(line)); first match wins on macOS"
                if strict {
                    throw ComposeError.invalidField(
                        "x-compose.hosts",
                        reason: message
                    )
                }
                warnings.append(HostDNSWarning(message: "Warning: \(message)"))
            }
        }
        return warnings
    }

    package static func isDevSuffixHostname(_ hostname: String) -> Bool {
        HostDNSHostnameValidation.isDevSuffixHostname(hostname)
    }

    private struct CollectedIssues {
        var warnings: [HostDNSWarning] = []
        var firstError: ComposeError?
    }

    private struct HostnameCollectionState {
        var hostnameOwners: [String: [String]] = [:]
        var collected = CollectedIssues()
    }

    private static func collectIssues(
        composeFile: ComposeFile,
        activeServiceNames: Set<String>,
        strict: Bool
    ) -> CollectedIssues {
        var state = HostnameCollectionState()

        for serviceName in activeServiceNames.sorted() {
            guard let service = composeFile.services[serviceName], !service.hostnames.isEmpty else {
                continue
            }
            collectServiceHostIssues(
                serviceName: serviceName,
                service: service,
                composeFile: composeFile,
                strict: strict,
                state: &state
            )
        }

        for (hostname, services) in state.hostnameOwners where services.count > 1 {
            let sorted = services.sorted()
            record(
                &state.collected,
                strict: strict,
                error: .duplicateHostDNSHostname(hostname: hostname, services: sorted),
                warning: "Host '\(hostname)' is declared by multiple services: \(sorted.joined(separator: ", "))"
            )
        }
        return state.collected
    }

    private static func collectServiceHostIssues(
        serviceName: String,
        service: ComposeService,
        composeFile: ComposeFile,
        strict: Bool,
        state: inout HostnameCollectionState
    ) {
        let onBridge = NetworkPlanning.serviceUsesBridgeNetwork(composeFile: composeFile, service: service)
        let hasStaticPort = firstStaticHostPort(service: service) != nil
        if onBridge, (service.deploy?.replicas ?? 1) > 1 {
            record(
                &state.collected,
                strict: strict,
                error: .invalidField(
                    "x-compose.hosts",
                    reason:
                        "Service '\(serviceName)' uses bridge networking with multiple replicas; "
                        + "host DNS maps one arbitrary replica IP"
                ),
                warning:
                    "Service '\(serviceName)' uses bridge networking with multiple replicas; "
                    + "host DNS maps one arbitrary replica IP"
            )
        }
        for rawHostname in service.hostnames {
            let hostname = normalizedHostname(rawHostname)
            if let reason = invalidHostnameReason(rawHostname) {
                record(
                    &state.collected,
                    strict: strict,
                    error: .invalidHostDNSHostname(hostname: rawHostname, reason: reason),
                    warning: "Invalid hostname '\(rawHostname)': \(reason)"
                )
                continue
            }
            if let warning = nonDevSuffixBridgeWarning(hostname: hostname, onBridge: onBridge) {
                state.collected.warnings.append(warning)
            }
            if !onBridge, !hasStaticPort {
                record(
                    &state.collected,
                    strict: strict,
                    error: .hostDNSNoPublishedPort(service: serviceName, hostname: hostname),
                    warning: "Service '\(serviceName)' declares host '\(hostname)' but has no published host port"
                )
            }
            state.hostnameOwners[hostname, default: []].append(serviceName)
        }
    }

    private static func record(
        _ collected: inout CollectedIssues,
        strict: Bool,
        error: ComposeError,
        warning: String
    ) {
        if strict, collected.firstError == nil {
            collected.firstError = error
        } else if !strict {
            collected.warnings.append(HostDNSWarning(message: "Warning: \(warning)"))
        }
    }

    package static func normalizedHostname(_ hostname: String) -> String {
        HostDNSHostnameValidation.normalizedHostname(hostname)
    }

    package static func invalidHostnameReason(_ hostname: String) -> String? {
        HostDNSHostnameValidation.invalidHostnameReason(hostname)
    }

    package static func firstStaticHostPort(service: ComposeService) -> String? {
        for port in service.ports {
            guard let spec = ComposeBindingKeys.parsePortSpec(port), let hostPort = spec.hostPort else {
                continue
            }
            return hostPort
        }
        return nil
    }
}
