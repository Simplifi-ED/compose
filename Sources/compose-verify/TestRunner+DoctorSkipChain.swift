import ComposeCore
import Foundation

extension TestRunner {
    mutating func runDoctorSkipChainTests() {
        runDoctorSkipChainMissingCLITest()
        runDoctorSkipChainVersionFailureTest()
        runDoctorSkipChainAPIDownTest()
        runDoctorSkipChainDiscoveryFailureTest()
        runDoctorSkipChainKernelProbeTimeoutTest()
        runDoctorEnvironmentForwardingTest()
    }

    private mutating func runDoctorSkipChainMissingCLITest() {
        let missingCLI = blockingAwait {
            await DoctorChecksRuntime.run(containerCLIPath: nil)
        }
        expect(missingCLI.first { $0.id == "container_cli" }?.status == .fail, "missing CLI fails")
        let skippedIDs = Set(missingCLI.filter { $0.status == .skipped }.map { $0.id })
        expect(
            skippedIDs == Set(DoctorSkip.containerCLIFailureIDs),
            "missing CLI skips downstream runtime checks"
        )
        expect(
            !missingCLI.contains { $0.id == "api_server" && $0.status == .fail },
            "missing CLI does not run API check"
        )
    }

    private mutating func runDoctorSkipChainVersionFailureTest() {
        struct VersionDown: Error {}
        let versionDown = blockingAwait {
            await DoctorChecksRuntime.run(
                containerCLIPath: "/usr/local/bin/container",
                dependencies: DoctorRuntimeDependencies(
                    runSubprocess: { _, args, _ in
                        if args == ["--version"] {
                            return DoctorSubprocessResult(
                                exitCode: 0,
                                stdout: "container CLI version 0.9.0 (build: release, commit: abc)",
                                stderr: ""
                            )
                        }
                        throw VersionDown()
                    },
                    listContainers: {}
                )
            )
        }
        expect(
            versionDown.first { $0.id == "container_version" }?.status == .fail,
            "below-minimum version fails"
        )
        let versionSkipped = Set(versionDown.filter { $0.status == .skipped }.map { $0.id })
        expect(
            versionSkipped == Set(DoctorSkip.containerVersionFailureIDs),
            "version failure skips downstream runtime checks"
        )
        expect(
            !versionDown.contains { $0.id == "api_server" && $0.status == .fail },
            "version failure does not run API check"
        )
    }

    private mutating func runDoctorSkipChainAPIDownTest() {
        struct APIDown: Error {}
        let apiDown = blockingAwait {
            await DoctorChecksRuntime.run(
                containerCLIPath: "/usr/local/bin/container",
                dependencies: DoctorRuntimeDependencies(
                    runSubprocess: { _, args, _ in
                        if args == ["--version"] {
                            return DoctorSubprocessResult(
                                exitCode: 0,
                                stdout: "container CLI version 1.0.0 (build: release, commit: abc)",
                                stderr: ""
                            )
                        }
                        throw APIDown()
                    },
                    listContainers: { throw APIDown() }
                )
            )
        }
        expect(apiDown.first { $0.id == "api_server" }?.status == .fail, "API down fails")
        let apiSkipped = Set(apiDown.filter { $0.status == .skipped }.map { $0.id })
        expect(
            apiSkipped == Set(DoctorSkip.apiServerFailureIDs),
            "API down skips discovery and kernel checks"
        )
        expect(
            !apiDown.contains { $0.id == "plugin_discovery" && $0.status == .fail },
            "API down does not run plugin discovery"
        )
    }

    private mutating func runDoctorSkipChainDiscoveryFailureTest() {
        struct DiscoveryDown: Error {}
        let composeHelp = """
        SUBCOMMANDS:
          up                      Start services
        """
        let discoveryFail = blockingAwait {
            await DoctorChecksRuntime.run(
                containerCLIPath: "/usr/local/bin/container",
                dependencies: DoctorRuntimeDependencies(
                    runSubprocess: { _, args, _ in
                        if args == ["--version"] {
                            return DoctorSubprocessResult(
                                exitCode: 0,
                                stdout: "container CLI version 1.0.0 (build: release, commit: abc)",
                                stderr: ""
                            )
                        }
                        if args == ["compose", "--help"] {
                            return DoctorSubprocessResult(exitCode: 0, stdout: composeHelp, stderr: "")
                        }
                        throw DiscoveryDown()
                    },
                    listContainers: {}
                )
            )
        }
        expect(
            discoveryFail.first { $0.id == "plugin_discovery" }?.status == .fail,
            "stale plugin help fails discovery"
        )
        let discoverySkipped = Set(discoveryFail.filter { $0.status == .skipped }.map { $0.id })
        expect(
            discoverySkipped == Set(DoctorSkip.pluginDiscoveryFailureIDs),
            "discovery failure skips kernel checks"
        )
        expect(
            !discoveryFail.contains { $0.id == "host_kernel" && $0.status == .fail },
            "discovery failure does not run kernel probe"
        )
    }

    private mutating func runDoctorEnvironmentForwardingTest() {
        let findings = blockingAwait {
            await DoctorChecks.run(
                environment: ["CUSTOM_DOCTOR_ENV": "1"],
                runtimeDependencies: DoctorRuntimeDependencies(
                    whichExecutable: { _, environment in
                        environment["CUSTOM_DOCTOR_ENV"] == "1" ? nil : "/unexpected/container"
                    },
                    listContainers: {}
                )
            )
        }
        expect(
            findings.first { $0.id == "container_cli" }?.status == .fail,
            "custom environment reaches whichExecutable"
        )
        expect(
            findings.first { $0.id == "plugin_bundle" }?.status == .skipped,
            "plugin bundle skipped when CLI missing"
        )
        expect(
            findings.first { $0.id == "plugin_writable" }?.status == .skipped,
            "plugin writable skipped when CLI missing"
        )
    }

    private mutating func runDoctorSkipChainKernelProbeTimeoutTest() {
        struct APIDown: Error {}
        let composeHelp = """
        SUBCOMMANDS:
        \(ComposeSubcommandRegistry.commandNames.map { "  \($0)    \($0) command" }.joined(separator: "\n"))

          See 'compose help <subcommand>' for detailed help.
        """
        let cachedProbeTimeout = blockingAwait {
            await DoctorChecksRuntime.run(
                containerCLIPath: "/usr/local/bin/container",
                dependencies: DoctorRuntimeDependencies(
                    runSubprocess: { _, args, timeout in
                        if args == ["--version"] {
                            return DoctorSubprocessResult(
                                exitCode: 0,
                                stdout: "container CLI version 1.0.0 (build: release, commit: abc)",
                                stderr: ""
                            )
                        }
                        if args == ["compose", "--help"] {
                            return DoctorSubprocessResult(exitCode: 0, stdout: composeHelp, stderr: "")
                        }
                        if args == ["image", "ls"] {
                            return DoctorSubprocessResult(
                                exitCode: 0,
                                stdout: "NAME TAG\nbusybox 1.36.1\n",
                                stderr: ""
                            )
                        }
                        if args.first == "run", timeout == DoctorRequirements.kernelProbeTimeout {
                            throw DoctorSubprocessError.timedOut("/usr/local/bin/container")
                        }
                        throw APIDown()
                    },
                    listContainers: {}
                )
            )
        }
        expect(
            cachedProbeTimeout.first { $0.id == "host_kernel" }?.status == .fail,
            "cached probe timeout fails kernel check"
        )
    }
}
