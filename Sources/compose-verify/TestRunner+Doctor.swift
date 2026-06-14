import ComposeCore
import Foundation

extension TestRunner {
    mutating func runDoctorTests() {
        runDoctorFindingTests()
        runDoctorVersionTests()
        runDoctorReportTests()
        runDoctorSkipTests()
        runDoctorSkipChainTests()
        runDoctorKernelProbeTests()
        runDoctorPluginPathTests()
        runDoctorRegistryTests()
        runDoctorRuntimeTests()
    }

    private mutating func runDoctorFindingTests() {
        let finding = DoctorFinding(
            id: "container_cli",
            title: "Container CLI on PATH",
            detail: "Found at /usr/local/bin/container.",
            remediation: "container system start",
            status: .pass,
            severity: .critical
        )
        do {
            let data = try JSONEncoder().encode(finding)
            let decoded = try JSONDecoder().decode(DoctorFinding.self, from: data)
            expect(decoded == finding, "DoctorFinding Codable round-trip")
        } catch {
            expect(false, "DoctorFinding Codable round-trip threw: \(error)")
        }
    }

    private mutating func runDoctorVersionTests() {
        expect(
            DoctorVersion.parse("container CLI version 1.0.0 (build: release, commit: ee848e3)") == "1.0.0",
            "parse container --version output"
        )
        expect(
            DoctorVersion.satisfiesMinimum("1.0.1", minimum: "1.0.0"),
            "newer version satisfies minimum"
        )
        expect(
            !DoctorVersion.satisfiesMinimum("0.9.9", minimum: "1.0.0"),
            "older version fails minimum"
        )
    }

    private mutating func runDoctorReportTests() {
        let findings = doctorReportFixtureFindings()
        runDoctorReportSummaryTests(findings: findings)
        runDoctorReportFormatTests(findings: findings)
    }

    private func doctorReportFixtureFindings() -> [DoctorFinding] {
        [
            DoctorFinding(
                id: "host_arch",
                title: "Host architecture",
                detail: "Running on Apple Silicon (arm64).",
                status: .pass,
                severity: .critical
            ),
            DoctorFinding(
                id: "rosetta",
                title: "Rosetta 2",
                detail: "Rosetta 2 is not installed.",
                status: .warn,
                severity: .advisory
            ),
            DoctorFinding(
                id: "api_server",
                title: "Container API server",
                detail: "Container API is not reachable.",
                status: .fail,
                severity: .critical
            ),
            DoctorFinding(
                id: "host_kernel",
                title: "Host kernel configuration",
                detail: "Skipped because the container API is not reachable.",
                status: .skipped,
                severity: .advisory
            )
        ]
    }

    private mutating func runDoctorReportSummaryTests(findings: [DoctorFinding]) {
        let summary = DoctorReport.summary(for: findings)
        expect(summary.passed == 1, "summary passed count")
        expect(summary.warnings == 1, "summary warnings count")
        expect(summary.critical == 1, "summary critical count")
        expect(summary.skipped == 1, "summary skipped count")
        expect(
            DoctorReport.summaryLine(for: findings)
                == "Summary: 1 passed, 1 warnings, 1 critical, 1 skipped",
            "summary line"
        )
        expect(DoctorReport.hasCriticalFailure(findings), "critical failure detected")
        expect(
            !DoctorReport.hasCriticalFailure(
                findings.filter { !($0.status == .fail && $0.severity == .critical) }
            ),
            "warn and skipped do not fail exit"
        )
    }

    private mutating func runDoctorReportFormatTests(findings: [DoctorFinding]) {
        let plainLines = DoctorReport.lines(for: [findings[0]], mode: .plain)
        expect(plainLines.first == "OK Host architecture", "plain pass prefix")
        expect(plainLines.last == "Summary: 1 passed, 0 warnings, 0 critical, 0 skipped", "plain summary")

        let interactiveLines = DoctorReport.lines(for: [findings[1]], mode: .interactive)
        expect(interactiveLines.first?.hasPrefix("⚠️") == true, "interactive warn prefix")
    }

    private mutating func runDoctorSkipTests() {
        let skipped = DoctorSkip.findings(
            ids: DoctorSkip.containerCLIFailureIDs,
            reason: "Skipped because container CLI was not found on PATH."
        )
        expect(skipped.count == DoctorSkip.containerCLIFailureIDs.count, "skip count for missing CLI")
        expect(skipped.allSatisfy { $0.status == .skipped }, "all skipped status")
        expect(
            skipped.allSatisfy { $0.detail == "Skipped because container CLI was not found on PATH." },
            "skip reason propagated"
        )
    }

    private mutating func runDoctorKernelProbeTests() {
        expect(
            DoctorKernelProbe.imageCached(
                in: """
                NAME        TAG             DIGEST
                busybox     1.36.1          abc123
                """
            ),
            "busybox 1.36.1 cached"
        )
        expect(
            !DoctorKernelProbe.imageCached(
                in: """
                NAME        TAG             DIGEST
                busybox     latest          abc123
                """
            ),
            "busybox latest alone is not probe tag"
        )
        expect(
            DoctorKernelProbe.classify(stderr: "kernel is not configured", stdout: "") == .kernel,
            "classify kernel stderr"
        )
        expect(
            DoctorKernelProbe.classify(stderr: "failed to pull image", stdout: "") == .registry,
            "classify registry stderr"
        )

        let cachedPass = DoctorKernelProbe.registryCachedFinding(imageCached: true)
        expect(cachedPass.status == .pass, "registry cached pass")

        let uncachedWarn = DoctorKernelProbe.registryCachedFinding(imageCached: false)
        expect(uncachedWarn.status == .warn, "registry uncached warn")

        let skippedKernel = DoctorKernelProbe.hostKernelFinding(outcome: .uncached)
        expect(skippedKernel.status == .skipped, "kernel skipped without cached image")

        let executionFailed = DoctorKernelProbe.hostKernelFinding(outcome: .executionFailed)
        expect(executionFailed.status == .fail, "kernel execution failure is critical")
    }

    private mutating func runDoctorPluginPathTests() {
        let resolved = PluginInstallPath.resolve(
            containerCLIPath: "/usr/local/bin/container",
            environment: [:]
        )
        expect(resolved?.installRoot == "/usr/local", "PKG install root")
        expect(
            resolved?.pluginDestination == "/usr/local/libexec/container-plugins/compose",
            "PKG plugin destination"
        )

        let brewResolved = PluginInstallPath.resolve(
            containerCLIPath: "/opt/homebrew/opt/container/bin/container",
            environment: ["HOMEBREW_PREFIX": "/opt/homebrew"]
        )
        expect(brewResolved?.installRoot == "/opt/homebrew/opt/container", "Homebrew install root")

        expect(
            PluginInstallPath.resolveInstallRoot(
                containerCLIPath: "/usr/local/bin/container",
                environment: ["CONTAINER_INSTALL_ROOT": "/custom/root"]
            ) == "/custom/root",
            "CONTAINER_INSTALL_ROOT override"
        )
    }

    private mutating func runDoctorRegistryTests() {
        expect(ComposeSubcommandRegistry.commandNames.contains("doctor"), "registry includes doctor")
        expect(ComposeSubcommandRegistry.commandNames.contains("up"), "registry includes up")
        expect(
            ComposeSubcommandRegistry.all.count == ComposeSubcommandRegistry.commandNames.count,
            "registry names align with command count"
        )
    }

    private mutating func runDoctorRuntimeTests() {
        expect(
            ComposeSubcommandRegistry.parseSubcommands(
                from: """
                SUBCOMMANDS:
                  up                      Start services
                  down                    Stop services
                  doctor                  Run checks

                  See 'compose help <subcommand>' for detailed help.
                """
            ) == Set(["up", "down", "doctor"]),
            "parse compose help subcommands"
        )

        expect(
            ComposeSubcommandRegistry.parseSubcommands(
                from: """
                SUBCOMMANDS:
                  top, stats              Display live resource usage for project services.
                """
            ) == Set(["top", "stats"]),
            "parse subcommand aliases from help"
        )

        let noisyHelp = """
        SUBCOMMANDS:
          up                      Start services
        removing stale containers before startup
          down                    Stop services
        """
        expect(
            ComposeSubcommandRegistry.parseSubcommands(from: noisyHelp) == Set(["up", "down"]),
            "parse ignores unindented help noise"
        )

        let helpMissingPause = """
        SUBCOMMANDS:
          up                      Start services
          down                    Stop services
        """
        let listed = ComposeSubcommandRegistry.parseSubcommands(from: helpMissingPause)
        let missing = Set(ComposeSubcommandRegistry.commandNames).subtracting(listed)
        expect(missing.contains("doctor"), "stale plugin help missing doctor")
        expect(missing.contains("pause"), "stale plugin help missing pause")
    }
}
