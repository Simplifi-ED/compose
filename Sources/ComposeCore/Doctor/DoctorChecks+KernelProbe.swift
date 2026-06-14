import Foundation

package enum DoctorKernelProbe {
    package enum FailureKind: Equatable, Sendable {
        case kernel
        case registry
        case unknown
    }

    package enum ProbeOutcome: Sendable {
        case uncached
        case executionFailed
        case probeFinished(DoctorSubprocessResult)
    }

    package static func imageCached(in imageListOutput: String) -> Bool {
        let lines = imageListOutput.split(whereSeparator: \.isNewline)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("NAME") || trimmed.hasPrefix("FIELD") {
                continue
            }
            let parts = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard parts.count >= 2 else { continue }
            let name = parts[0].lowercased()
            let tag = parts[1].lowercased()
            if name.contains("busybox") {
                if tag == DoctorRequirements.probeImageTag {
                    return true
                }
            }
            if trimmed.localizedCaseInsensitiveContains(DoctorRequirements.probeImageReference) {
                return true
            }
        }
        return false
    }

    package static func classify(stderr: String, stdout: String) -> FailureKind {
        let combined = (stderr + "\n" + stdout).lowercased()
        if combined.contains("kernel") || combined.contains("runtime")
            || combined.contains("hv_") || combined.contains("virtualization") {
            return .kernel
        }
        if combined.contains("pull") || combined.contains("registry") || combined.contains("network")
            || combined.contains("dial") || combined.contains("resolve") || combined.contains("tls")
            || combined.contains("timeout") || combined.contains("unauthorized") {
            return .registry
        }
        return .unknown
    }

    package static func registryCachedFinding(imageCached: Bool) -> DoctorFinding {
        if imageCached {
            return DoctorFinding(
                id: "registry_cached",
                title: DoctorCheckCatalog.title(for: "registry_cached"),
                detail: "\(DoctorRequirements.probeImageReference) is available locally.",
                status: .pass,
                severity: .advisory
            )
        }
        return DoctorFinding(
            id: "registry_cached",
            title: DoctorCheckCatalog.title(for: "registry_cached"),
            detail: "\(DoctorRequirements.probeImageReference) is not cached locally.",
            remediation: """
            container image pull \(DoctorRequirements.probeImageReference)
            # Pull requires network access; kernel verification is skipped until the image is cached.
            """,
            status: .warn,
            severity: .advisory
        )
    }

    package static func hostKernelFinding(outcome: ProbeOutcome) -> DoctorFinding {
        switch outcome {
        case .uncached:
            return DoctorFinding(
                id: "host_kernel",
                title: DoctorCheckCatalog.title(for: "host_kernel"),
                detail: "Skipped because the probe image is not cached; pull manually to verify kernel.",
                status: .skipped,
                severity: .advisory
            )
        case .executionFailed:
            return DoctorFinding(
                id: "host_kernel",
                title: DoctorCheckCatalog.title(for: "host_kernel"),
                detail: "Container runtime probe could not be executed.",
                remediation: """
                container system start
                container image pull \(DoctorRequirements.probeImageReference)
                """,
                status: .fail,
                severity: .critical
            )
        case .probeFinished(let probeResult):
            return hostKernelFinding(probeResult: probeResult)
        }
    }

    private static func hostKernelFinding(
        probeResult: DoctorSubprocessResult
    ) -> DoctorFinding {
        if probeResult.exitCode == 0 {
            return DoctorFinding(
                id: "host_kernel",
                title: DoctorCheckCatalog.title(for: "host_kernel"),
                detail: "Container runtime probe succeeded.",
                status: .pass,
                severity: .critical
            )
        }

        let kind = classify(stderr: probeResult.stderr, stdout: probeResult.stdout)
        return failedKernelFinding(kind: kind)
    }

    private static func failedKernelFinding(kind: FailureKind) -> DoctorFinding {
        switch kind {
        case .kernel:
            return DoctorFinding(
                id: "host_kernel",
                title: DoctorCheckCatalog.title(for: "host_kernel"),
                detail: "Container runtime probe failed with a kernel or runtime error.",
                remediation: "container system kernel set --url <kernel-tarball-url>",
                status: .fail,
                severity: .critical
            )
        case .registry:
            return DoctorFinding(
                id: "host_kernel",
                title: DoctorCheckCatalog.title(for: "host_kernel"),
                detail: "Container runtime probe failed with a registry or network error.",
                remediation: """
                Check network access, then pull the probe image:
                container image pull \(DoctorRequirements.probeImageReference)
                """,
                status: .warn,
                severity: .advisory
            )
        case .unknown:
            return DoctorFinding(
                id: "host_kernel",
                title: DoctorCheckCatalog.title(for: "host_kernel"),
                detail: "Container runtime probe failed.",
                remediation: """
                container system kernel set --url <kernel-tarball-url>
                container system start
                """,
                status: .fail,
                severity: .critical
            )
        }
    }
}
