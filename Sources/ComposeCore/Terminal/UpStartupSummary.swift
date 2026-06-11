import Foundation

/// Aligned per-service summary block printed to stdout after a successful `up`.
///
/// One row per service in startup order, with the service name padded to a
/// shared column width followed by its container names:
///
///     web  demo_web_1  demo_web_2
///     db   demo_db_1
package enum UpStartupSummary {
    package static func lines(for plans: [ServicePlan]) -> [String] {
        guard !plans.isEmpty else { return [] }

        var serviceOrder: [String] = []
        var containersByService: [String: [String]] = [:]
        for plan in plans {
            if containersByService[plan.serviceName] == nil {
                serviceOrder.append(plan.serviceName)
            }
            containersByService[plan.serviceName, default: []].append(plan.name)
        }

        let width = serviceOrder.map(\.count).max() ?? 0
        return serviceOrder.map { serviceName in
            let names = containersByService[serviceName, default: []].joined(separator: "  ")
            return "\(TerminalLayout.fit(serviceName, width: width))  \(names)"
        }
    }
}
