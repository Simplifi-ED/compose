import Foundation

/// Summary lines printed after `compose pause` / `compose unpause`.
package enum PauseSummary {
    private static let countStyle = IntegerFormatStyle<Int>().grouping(.never)

    package static func summaryLine(
        operation: ContainerLifecycle.Operation,
        names: [String]
    ) -> String {
        let count = names.count
        let verb = operation == .pause ? "Paused" : "Unpaused"
        let list = names.joined(separator: ", ")
        if count == 1 {
            return "\(verb) \(count.formatted(countStyle)) container: \(list)"
        }
        return "\(verb) \(count.formatted(countStyle)) containers: \(list)"
    }

    package static func emptyMessage(operation: ContainerLifecycle.Operation) -> String {
        switch operation {
        case .pause:
            "No running containers to pause."
        case .unpause:
            "No paused containers to unpause."
        }
    }
}
