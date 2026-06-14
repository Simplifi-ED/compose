import Foundation

package enum PluginInstallPath {
    package struct Resolved: Sendable, Equatable {
        package let installRoot: String
        package let pluginDestination: String
        package let composeBinary: String
        package let configFile: String
    }

    package static func resolve(
        containerCLIPath: String?,
        environment: [String: String]
    ) -> Resolved? {
        guard let containerCLIPath, !containerCLIPath.isEmpty else { return nil }
        let installRoot = resolveInstallRoot(
            containerCLIPath: containerCLIPath,
            environment: environment
        )
        let pluginDestination = (installRoot as NSString)
            .appendingPathComponent("libexec/container-plugins/compose")
        return Resolved(
            installRoot: installRoot,
            pluginDestination: pluginDestination,
            composeBinary: (pluginDestination as NSString).appendingPathComponent("bin/compose"),
            configFile: (pluginDestination as NSString).appendingPathComponent("config.toml")
        )
    }

    package static func resolveInstallRoot(
        containerCLIPath: String,
        environment: [String: String]
    ) -> String {
        if let override = environment["CONTAINER_INSTALL_ROOT"]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !override.isEmpty {
            return override
        }

        if let brewRoot = brewInstallRoot(
            containerCLIPath: containerCLIPath,
            environment: environment
        ) {
            return brewRoot
        }

        let containerURL = URL(fileURLWithPath: containerCLIPath)
        return containerURL.deletingLastPathComponent().deletingLastPathComponent().path
    }

    private static func brewInstallRoot(
        containerCLIPath: String,
        environment: [String: String]
    ) -> String? {
        let brewPrefix = environment["HOMEBREW_PREFIX"]
            ?? environment["HOMEBREW_OPT"]
            ?? defaultHomebrewPrefix(environment: environment)
        guard let brewPrefix, !brewPrefix.isEmpty else { return nil }

        let resolvedCLIPath = URL(fileURLWithPath: containerCLIPath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
        let brewContainerBin = (brewPrefix as NSString)
            .appendingPathComponent("opt/container/bin/container")
        let brewContainerRoot = (brewPrefix as NSString).appendingPathComponent("opt/container")
        if resolvedCLIPath == brewContainerBin || resolvedCLIPath.hasPrefix(brewContainerRoot + "/") {
            return (brewPrefix as NSString).appendingPathComponent("opt/container")
        }
        return nil
    }

    private static func defaultHomebrewPrefix(environment: [String: String]) -> String? {
        if let prefix = environment["HOMEBREW_PREFIX"], !prefix.isEmpty {
            return prefix
        }
        for candidate in ["/opt/homebrew", "/usr/local"] where FileManager.default.fileExists(atPath: candidate) {
            return candidate
        }
        return nil
    }
}
