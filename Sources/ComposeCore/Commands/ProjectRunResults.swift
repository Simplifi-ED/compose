import Foundation

package struct ProjectListResult: Sendable, Equatable {
    package let rows: [ProjectStatusRow]
    package let warnings: [String]

    package init(rows: [ProjectStatusRow], warnings: [String] = []) {
        self.rows = rows
        self.warnings = warnings
    }
}

package struct ProjectMutationResult: Sendable, Equatable {
    package let affectedContainers: [String]
    package let warnings: [String]

    package init(affectedContainers: [String], warnings: [String] = []) {
        self.affectedContainers = affectedContainers
        self.warnings = warnings
    }
}
