import ContainerAPIClient
import Foundation

package struct DoctorRuntimeDependencies: Sendable {
    package var environment: [String: String]
    package var whichExecutable: @Sendable (String, [String: String]) async -> String?
    package var runSubprocess: @Sendable (String, [String], Duration) async throws -> DoctorSubprocessResult
    package var listContainers: @Sendable () async throws -> Void

    package init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        whichExecutable: @escaping @Sendable (String, [String: String]) async -> String? = DoctorSubprocess.which,
        runSubprocess: (@Sendable (String, [String], Duration) async throws -> DoctorSubprocessResult)? = nil,
        listContainers: @escaping @Sendable () async throws -> Void = {
            _ = try await ContainerClient().list(filters: .init())
        }
    ) {
        self.environment = environment
        self.whichExecutable = whichExecutable
        self.listContainers = listContainers
        if let runSubprocess {
            self.runSubprocess = runSubprocess
        } else {
            self.runSubprocess = { path, args, timeout in
                try await DoctorSubprocess.runCapturing(
                    executable: path,
                    arguments: args,
                    environment: environment,
                    timeout: timeout
                )
            }
        }
    }
}

package enum DoctorChecksRuntime {
    package static func run(
        containerCLIPath: String?,
        dependencies: DoctorRuntimeDependencies = DoctorRuntimeDependencies()
    ) async -> [DoctorFinding] {
        var findings: [DoctorFinding] = []

        let cliFinding = await containerCLI(containerCLIPath: containerCLIPath)
        findings.append(cliFinding)
        guard cliFinding.status != .fail, let containerPath = containerCLIPath else {
            findings.append(contentsOf: DoctorSkip.findings(
                ids: DoctorSkip.containerCLIFailureIDs,
                reason: DoctorSkip.containerCLIMissingReason
            ))
            return findings
        }

        let versionFinding = await containerVersion(
            containerPath: containerPath,
            dependencies: dependencies
        )
        findings.append(versionFinding)
        if versionFinding.status == .fail {
            let skipReason = versionFinding.detail.hasPrefix("Could not parse")
                ? "Skipped because container CLI version could not be verified."
                : "Skipped because container CLI version is below the minimum."
            findings.append(contentsOf: DoctorSkip.findings(
                ids: DoctorSkip.containerVersionFailureIDs,
                reason: skipReason
            ))
            return findings
        }

        let apiFinding = await apiServer(dependencies: dependencies)
        findings.append(apiFinding)
        if apiFinding.status == .fail {
            findings.append(contentsOf: DoctorSkip.findings(
                ids: DoctorSkip.apiServerFailureIDs,
                reason: "Skipped because the container API is not reachable."
            ))
            return findings
        }

        let tail = await discoveryAndKernelFindings(
            containerPath: containerPath,
            dependencies: dependencies
        )
        return findings + tail
    }

    private static func discoveryAndKernelFindings(
        containerPath: String,
        dependencies: DoctorRuntimeDependencies
    ) async -> [DoctorFinding] {
        var findings: [DoctorFinding] = []
        let discoveryFinding = await DoctorChecksDiscovery.pluginDiscovery(
            containerPath: containerPath,
            dependencies: dependencies
        )
        findings.append(discoveryFinding)
        if discoveryFinding.status == .fail {
            findings.append(contentsOf: DoctorSkip.findings(
                ids: DoctorSkip.pluginDiscoveryFailureIDs,
                reason: "Skipped because compose plugin discovery failed."
            ))
            return findings
        }
        findings.append(contentsOf: await kernelFindings(
            containerPath: containerPath,
            dependencies: dependencies
        ))
        return findings
    }

    private static func kernelFindings(
        containerPath: String,
        dependencies: DoctorRuntimeDependencies
    ) async -> [DoctorFinding] {
        let imageList: DoctorSubprocessResult
        do {
            imageList = try await dependencies.runSubprocess(
                containerPath,
                ["image", "ls"],
                DoctorRequirements.subprocessTimeout
            )
        } catch {
            return [
                DoctorFinding(
                    id: "registry_cached",
                    title: DoctorCheckCatalog.title(for: "registry_cached"),
                    detail: "Could not list local images.",
                    remediation: "container system start",
                    status: .warn,
                    severity: .advisory
                ),
                DoctorFinding(
                    id: "host_kernel",
                    title: DoctorCheckCatalog.title(for: "host_kernel"),
                    detail: "Skipped because local image listing failed.",
                    status: .skipped,
                    severity: .advisory
                )
            ]
        }

        let imageCached = DoctorKernelProbe.imageCached(in: imageList.stdout)
        var findings = [DoctorKernelProbe.registryCachedFinding(imageCached: imageCached)]

        guard imageCached else {
            findings.append(DoctorKernelProbe.hostKernelFinding(outcome: .uncached))
            return findings
        }

        do {
            let probe = try await dependencies.runSubprocess(
                containerPath,
                ["run", "--rm", DoctorRequirements.probeImageReference, "true"],
                DoctorRequirements.kernelProbeTimeout
            )
            findings.append(DoctorKernelProbe.hostKernelFinding(outcome: .probeFinished(probe)))
        } catch {
            findings.append(DoctorKernelProbe.hostKernelFinding(outcome: .executionFailed))
        }
        return findings
    }

    package static func containerCLI(containerCLIPath: String?) async -> DoctorFinding {
        if let path = containerCLIPath {
            return DoctorFinding(
                id: "container_cli",
                title: DoctorCheckCatalog.title(for: "container_cli"),
                detail: "Found at \(path).",
                status: .pass,
                severity: .critical
            )
        }
        return DoctorFinding(
            id: "container_cli",
            title: DoctorCheckCatalog.title(for: "container_cli"),
            detail: "The container command was not found on PATH.",
            remediation: """
            brew install container
            # or install Apple's container PKG from https://github.com/apple/container
            """,
            status: .fail,
            severity: .critical
        )
    }

    package static func containerVersion(
        containerPath: String,
        dependencies: DoctorRuntimeDependencies
    ) async -> DoctorFinding {
        guard let result = try? await dependencies.runSubprocess(
            containerPath,
            ["--version"],
            DoctorRequirements.subprocessTimeout
        ),
            let version = DoctorVersion.parse(result.stdout)
        else {
            return DoctorFinding(
                id: "container_version",
                title: DoctorCheckCatalog.title(for: "container_version"),
                detail: "Could not parse container CLI version output.",
                remediation: "Upgrade container to \(DoctorRequirements.minimumContainerVersion) or newer.",
                status: .fail,
                severity: .critical
            )
        }

        if DoctorVersion.satisfiesMinimum(version, minimum: DoctorRequirements.minimumContainerVersion) {
            return DoctorFinding(
                id: "container_version",
                title: DoctorCheckCatalog.title(for: "container_version"),
                detail: "Running container \(version) (minimum \(DoctorRequirements.minimumContainerVersion)).",
                status: .pass,
                severity: .critical
            )
        }

        return DoctorFinding(
            id: "container_version",
            title: DoctorCheckCatalog.title(for: "container_version"),
            detail: "Running container \(version); minimum required is \(DoctorRequirements.minimumContainerVersion).",
            remediation: "Upgrade the container CLI to \(DoctorRequirements.minimumContainerVersion) or newer.",
            status: .fail,
            severity: .critical
        )
    }

    package static func apiServer(
        dependencies: DoctorRuntimeDependencies
    ) async -> DoctorFinding {
        do {
            try await dependencies.listContainers()
            return DoctorFinding(
                id: "api_server",
                title: DoctorCheckCatalog.title(for: "api_server"),
                detail: "Container API is reachable.",
                status: .pass,
                severity: .critical
            )
        } catch {
            return DoctorFinding(
                id: "api_server",
                title: DoctorCheckCatalog.title(for: "api_server"),
                detail: "Container API is not reachable.",
                remediation: "container system start",
                status: .fail,
                severity: .critical
            )
        }
    }
}
