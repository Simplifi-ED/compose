import Foundation

public struct HealthGate: Sendable, Equatable {
    public let dependencyService: String
    public let condition: DependsOnCondition
    public let containerNames: [String]

    public init(
        dependencyService: String,
        condition: DependsOnCondition,
        containerNames: [String]
    ) {
        self.dependencyService = dependencyService
        self.condition = condition
        self.containerNames = containerNames
    }
}

extension DependsOnCondition {
    /// Readiness gates for one dependency run in this order.
    package var readinessSortOrder: Int {
        switch self {
        case .orderingOnly:
            return 0
        case .serviceStarted:
            return 1
        case .serviceHealthy:
            return 2
        case .serviceCompletedSuccessfully:
            return 3
        }
    }
}
