import Foundation

package enum WorkspaceHygieneOutput {
    static func printOrphanRemovalSummary(count: Int, names: [String]) {
        guard count > 0 else { return }
        let nameList = names.joined(separator: ", ")
        print("Removed \(count) orphan container(s): \(nameList)")
    }

    static func warnOrphanRemovalSkipped(_ reason: String) {
        fputs("Warning: couldn't remove orphan containers: \(reason). Continuing.\n", stderr)
    }

    package static func listContainersFailureMessage(_ error: Error) -> String {
        "couldn't list project containers: \(error.localizedDescription)"
    }

    package static func orphanRemovalFailureMessage(_ error: Error) -> String {
        if let compose = error as? ComposeError,
           case .multipleServiceFailures(let failures) = compose {
            let names = failures.map(\.service).sorted().joined(separator: ", ")
            return "failed to remove some orphan container(s) (\(names))"
        }
        return error.localizedDescription
    }
}
