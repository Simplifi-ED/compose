import Foundation

public enum ComposeLabels {
    public static let project = "com.docker.compose.project"
    public static let service = "com.docker.compose.service"
    public static let containerNumber = "com.docker.compose.container-number"

    public static func runFlags(projectName: String, serviceName: String, containerNumber: Int = 1) -> [String] {
        [
            "-l", "\(project)=\(projectName)",
            "-l", "\(service)=\(serviceName)",
            "-l", "\(Self.containerNumber)=\(containerNumber)"
        ]
    }
}
