import Foundation

public enum ComposeLabels {
    public static let project = "com.docker.compose.project"
    public static let service = "com.docker.compose.service"

    public static func runFlags(projectName: String, serviceName: String) -> [String] {
        ["-l", "\(project)=\(projectName)", "-l", "\(service)=\(serviceName)"]
    }
}
