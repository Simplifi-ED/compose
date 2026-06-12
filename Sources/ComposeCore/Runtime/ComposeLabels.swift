import Foundation

public enum ComposeLabels {
    public static let project = "com.docker.compose.project"
    public static let service = "com.docker.compose.service"
    public static let containerNumber = "com.docker.compose.container-number"
    public static let machine = "com.docker.compose.machine"
    public static let network = "com.docker.compose.network"

    /// Labels stamped on project-scoped networks at `network create` time.
    package static func networkLabels(projectName: String, logicalName: String) -> [String: String] {
        [
            project: projectName,
            network: logicalName
        ]
    }

    public static func runFlags(
        projectName: String,
        serviceName: String,
        containerNumber: Int = 1,
        machineName: String? = nil
    ) -> [String] {
        var flags = [
            "-l", "\(project)=\(projectName)",
            "-l", "\(service)=\(serviceName)",
            "-l", "\(Self.containerNumber)=\(containerNumber)"
        ]
        if let machineName {
            flags.append(contentsOf: ["-l", "\(machine)=\(machineName)"])
        }
        return flags
    }
}
