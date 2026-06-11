import Foundation

public struct ServicePlan: Sendable, Equatable {
    public let serviceName: String
    public let name: String
    public let runArguments: [String]

    public init(serviceName: String, name: String, runArguments: [String]) {
        self.serviceName = serviceName
        self.name = name
        self.runArguments = runArguments
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
