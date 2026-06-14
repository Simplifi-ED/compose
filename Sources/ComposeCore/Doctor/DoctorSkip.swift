import Foundation

package enum DoctorSkip {
    package static let containerCLIFailureIDs = [
        "container_version",
        "api_server",
        "host_kernel",
        "registry_cached",
        "plugin_discovery"
    ]

    package static let containerVersionFailureIDs = [
        "api_server",
        "host_kernel",
        "registry_cached",
        "plugin_discovery"
    ]

    package static let apiServerFailureIDs = [
        "host_kernel",
        "registry_cached",
        "plugin_discovery"
    ]

    package static let pluginDiscoveryFailureIDs = [
        "host_kernel",
        "registry_cached"
    ]

    package static let containerCLIMissingReason =
        "Skipped because container CLI was not found on PATH."

    package static func findings(
        ids: [String],
        reason: String
    ) -> [DoctorFinding] {
        ids.map { id in
            DoctorFinding(
                id: id,
                title: DoctorCheckCatalog.title(for: id),
                detail: reason,
                status: .skipped,
                severity: .advisory
            )
        }
    }
}

package enum DoctorCheckCatalog {
    private static let titles: [String: String] = [
        "host_arch": "Host architecture",
        "disk_temp": "Temporary volume space",
        "disk_staging": "Compose staging volume space",
        "rosetta": "Rosetta 2",
        "plugin_bundle": "Compose plugin bundle",
        "plugin_writable": "Plugin install directory writable",
        "container_cli": "Container CLI on PATH",
        "container_version": "Container CLI version",
        "api_server": "Container API server",
        "host_kernel": "Host kernel configuration",
        "registry_cached": "Local probe image cache",
        "plugin_discovery": "Compose plugin discovery"
    ]

    package static func title(for id: String) -> String {
        titles[id] ?? id.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
