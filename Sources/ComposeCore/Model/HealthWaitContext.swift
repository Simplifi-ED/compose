import Foundation

public struct HealthWaitContext: Sendable {
    public let services: [String: ComposeService]
    public let projectName: String
    public let scaleOverrides: [String: Int]

    public init(
        services: [String: ComposeService],
        projectName: String,
        scaleOverrides: [String: Int] = [:]
    ) {
        self.services = services
        self.projectName = projectName
        self.scaleOverrides = scaleOverrides
    }
}
