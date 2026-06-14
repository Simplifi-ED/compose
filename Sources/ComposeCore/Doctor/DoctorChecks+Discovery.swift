import Foundation

package enum DoctorChecksDiscovery {
    package static func pluginDiscovery(
        containerPath: String,
        dependencies: DoctorRuntimeDependencies
    ) async -> DoctorFinding {
        guard let result = try? await dependencies.runSubprocess(
            containerPath,
            ["compose", "--help"],
            DoctorRequirements.subprocessTimeout
        ) else {
            return DoctorFinding(
                id: "plugin_discovery",
                title: DoctorCheckCatalog.title(for: "plugin_discovery"),
                detail: "Could not run container compose --help.",
                remediation: "container system start",
                status: .fail,
                severity: .critical
            )
        }

        let listed = ComposeSubcommandRegistry.parseSubcommands(from: result.stdout + "\n" + result.stderr)
        let expected = Set(ComposeSubcommandRegistry.commandNames)
        let missing = expected.subtracting(listed).sorted()

        if missing.isEmpty {
            return DoctorFinding(
                id: "plugin_discovery",
                title: DoctorCheckCatalog.title(for: "plugin_discovery"),
                detail: "All \(expected.count) compose subcommands are registered.",
                status: .pass,
                severity: .critical
            )
        }

        let pluginPath = PluginInstallPath.resolve(
            containerCLIPath: containerPath,
            environment: dependencies.environment
        )
        let pathHint = pluginPath?.pluginDestination ?? "{INSTALL_ROOT}/libexec/container-plugins/compose"

        return DoctorFinding(
            id: "plugin_discovery",
            title: DoctorCheckCatalog.title(for: "plugin_discovery"),
            detail: "Missing subcommands: \(missing.joined(separator: ", ")).",
            remediation: """
            container system start
            # Verify plugin at \(pathHint)
            ./scripts/install.sh
            """,
            status: .fail,
            severity: .critical
        )
    }
}
