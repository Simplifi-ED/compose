import Foundation

enum WorkspaceHygieneOutput {
    static func printOrphanRemovalSummary(count: Int, names: [String]) {
        guard count > 0 else { return }
        let nameList = names.joined(separator: ", ")
        print("Removed \(count) orphan container(s): \(nameList)")
    }

    static func warnOrphanRemovalSkipped(_ reason: String) {
        fputs("Warning: couldn't remove orphan containers: \(reason). Continuing.\n", stderr)
    }
}
