import Foundation

package enum DoctorChecksEnvironment {
    package static func hostArchitecture(
        machine: String = currentMachine()
    ) -> DoctorFinding {
        if machine == "arm64" {
            return DoctorFinding(
                id: "host_arch",
                title: DoctorCheckCatalog.title(for: "host_arch"),
                detail: "Running on Apple Silicon (arm64).",
                status: .pass,
                severity: .critical
            )
        }
        return DoctorFinding(
            id: "host_arch",
            title: DoctorCheckCatalog.title(for: "host_arch"),
            detail: "Detected \(machine). container compose requires Apple Silicon.",
            remediation: "Run on an Apple Silicon Mac (arm64).",
            status: .fail,
            severity: .critical
        )
    }

    package static func diskSpace(
        id: String,
        volumeURL: URL
    ) -> DoctorFinding {
        let title = DoctorCheckCatalog.title(for: id)
        let available = availableBytes(at: volumeURL) ?? 0
        let formatted = ByteCountFormatStyle(style: .file).format(available)
        if available < DoctorRequirements.diskFailThresholdBytes {
            return DoctorFinding(
                id: id,
                title: title,
                detail: "\(formatted) free on \(volumeURL.path).",
                remediation: "Free disk space on this volume before running compose workloads.",
                status: .fail,
                severity: .critical
            )
        }
        if available < DoctorRequirements.diskWarnThresholdBytes {
            return DoctorFinding(
                id: id,
                title: title,
                detail: "\(formatted) free on \(volumeURL.path).",
                remediation: "Consider freeing disk space before large image builds or volume mounts.",
                status: .warn,
                severity: .advisory
            )
        }
        return DoctorFinding(
            id: id,
            title: title,
            detail: "\(formatted) free on \(volumeURL.path).",
            status: .pass,
            severity: .advisory
        )
    }

    package static func rosettaInstalled() -> DoctorFinding {
        let rosettaPath = "/Library/Apple/usr/share/rosetta/rosettad"
        if FileManager.default.fileExists(atPath: rosettaPath) {
            return DoctorFinding(
                id: "rosetta",
                title: DoctorCheckCatalog.title(for: "rosetta"),
                detail: "Rosetta 2 is installed.",
                status: .pass,
                severity: .advisory
            )
        }
        return DoctorFinding(
            id: "rosetta",
            title: DoctorCheckCatalog.title(for: "rosetta"),
            detail: "Rosetta 2 is not installed.",
            remediation: "softwareupdate --install-rosetta",
            status: .warn,
            severity: .advisory
        )
    }

    package static func pluginBundle(
        pluginPath: PluginInstallPath.Resolved?
    ) -> DoctorFinding {
        guard let pluginPath else {
            return DoctorFinding(
                id: "plugin_bundle",
                title: DoctorCheckCatalog.title(for: "plugin_bundle"),
                detail: "Could not resolve the expected plugin install path.",
                remediation: """
                Install the compose plugin with ./scripts/install.sh
                or brew install simplifi-ed/compose/container-compose.
                """,
                status: .fail,
                severity: .critical
            )
        }

        var isDirectory: ObjCBool = false
        let binaryExists = FileManager.default.fileExists(
            atPath: pluginPath.composeBinary,
            isDirectory: &isDirectory
        ) && !isDirectory.boolValue
        let configExists = FileManager.default.fileExists(atPath: pluginPath.configFile)

        if binaryExists && configExists {
            return DoctorFinding(
                id: "plugin_bundle",
                title: DoctorCheckCatalog.title(for: "plugin_bundle"),
                detail: "Plugin files are present at \(pluginPath.pluginDestination).",
                status: .pass,
                severity: .critical
            )
        }

        var missing: [String] = []
        if !binaryExists { missing.append("bin/compose") }
        if !configExists { missing.append("config.toml") }
        return DoctorFinding(
            id: "plugin_bundle",
            title: DoctorCheckCatalog.title(for: "plugin_bundle"),
            detail: "Missing \(missing.joined(separator: ", ")) under \(pluginPath.pluginDestination).",
            remediation: """
            ./scripts/install.sh
            # or: brew install simplifi-ed/compose/container-compose
            """,
            status: .fail,
            severity: .critical
        )
    }

    package static func pluginWritable(
        pluginPath: PluginInstallPath.Resolved?
    ) -> DoctorFinding {
        guard let pluginPath else {
            return DoctorFinding(
                id: "plugin_writable",
                title: DoctorCheckCatalog.title(for: "plugin_writable"),
                detail: "Could not resolve the plugin install path.",
                status: .warn,
                severity: .advisory
            )
        }

        let parent = (pluginPath.pluginDestination as NSString).deletingLastPathComponent
        if FileManager.default.isWritableFile(atPath: parent) {
            return DoctorFinding(
                id: "plugin_writable",
                title: DoctorCheckCatalog.title(for: "plugin_writable"),
                detail: "\(parent) is writable by the current user.",
                status: .pass,
                severity: .advisory
            )
        }

        return DoctorFinding(
            id: "plugin_writable",
            title: DoctorCheckCatalog.title(for: "plugin_writable"),
            detail: "\(parent) is not writable by the current user.",
            remediation: """
            sudo mkdir -p "\(parent)"
            sudo cp -R dist/compose/* "\(pluginPath.pluginDestination)/"
            sudo chmod 755 "\(pluginPath.composeBinary)"
            """,
            status: .warn,
            severity: .advisory
        )
    }

    package static func runParallel(
        containerCLIPath: String?,
        pluginPath: PluginInstallPath.Resolved?
    ) async -> [DoctorFinding] {
        await withTaskGroup(of: DoctorFinding.self) { group in
            group.addTask { hostArchitecture() }
            group.addTask {
                diskSpace(
                    id: "disk_temp",
                    volumeURL: FileManager.default.temporaryDirectory
                )
            }
            group.addTask {
                diskSpace(
                    id: "disk_staging",
                    volumeURL: ComposeFileStaging.stagingRoot()
                )
            }
            group.addTask { rosettaInstalled() }
            group.addTask {
                if containerCLIPath == nil {
                    return DoctorSkip.findings(
                        ids: ["plugin_bundle"],
                        reason: DoctorSkip.containerCLIMissingReason
                    )[0]
                }
                return pluginBundle(pluginPath: pluginPath)
            }
            group.addTask {
                if containerCLIPath == nil {
                    return DoctorSkip.findings(
                        ids: ["plugin_writable"],
                        reason: DoctorSkip.containerCLIMissingReason
                    )[0]
                }
                return pluginWritable(pluginPath: pluginPath)
            }

            var findings: [DoctorFinding] = []
            for await finding in group {
                findings.append(finding)
            }
            return findings.sorted { $0.id < $1.id }
        }
    }

    private static func currentMachine() -> String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        let bytes = machine.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(bytes: bytes, encoding: .utf8) ?? "unknown"
    }

    private static func availableBytes(at url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
            let capacity = values.volumeAvailableCapacityForImportantUsage
        else {
            return nil
        }
        return capacity
    }
}
