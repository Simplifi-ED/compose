import Foundation

public enum DependsOnCondition: String, Sendable, Equatable {
  /// List-form `depends_on` — topological order only, no readiness wait.
  case orderingOnly
  case serviceStarted = "service_started"
  case serviceHealthy = "service_healthy"

  package static func parse(_ raw: String) throws -> DependsOnCondition {
    guard let condition = DependsOnCondition(rawValue: raw) else {
      throw ComposeError.invalidField(
        "depends_on",
        reason: "invalid condition '\(raw)'. Use service_started or service_healthy."
      )
    }
    return condition
  }
}

public struct ComposeDependency: Sendable, Equatable {
  public let service: String
  public let condition: DependsOnCondition

  public init(service: String, condition: DependsOnCondition = .orderingOnly) {
    self.service = service
    self.condition = condition
  }

  package var requiresReadinessWait: Bool {
    switch condition {
    case .orderingOnly:
      return false
    case .serviceStarted, .serviceHealthy:
      return true
    }
  }
}

extension Array where Element == ComposeDependency {
  package var serviceNames: [String] {
    map(\.service)
  }
}
