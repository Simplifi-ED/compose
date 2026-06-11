import Foundation

public struct ServicePlan: Sendable, Equatable {
    public let serviceName: String
    public let name: String
    public let runArguments: [String]
    /// 1-based replica index within the service; one-off `run` plans stay at 1.
    public let replicaIndex: Int

    public init(serviceName: String, name: String, runArguments: [String], replicaIndex: Int = 1) {
        self.serviceName = serviceName
        self.name = name
        self.runArguments = runArguments
        self.replicaIndex = replicaIndex
    }
}

package struct RunPlanOptions: Sendable, Equatable {
    package let removeContainer: Bool
    package let commandOverride: [String]?
    package let interactive: Bool
    package let processTerminal: Bool
    package let nameSuffix: String

    package init(
        removeContainer: Bool,
        commandOverride: [String]?,
        interactive: Bool,
        processTerminal: Bool,
        nameSuffix: String
    ) {
        self.removeContainer = removeContainer
        self.commandOverride = commandOverride
        self.interactive = interactive
        self.processTerminal = processTerminal
        self.nameSuffix = nameSuffix
    }
}
