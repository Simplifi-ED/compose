import Foundation

/// Fixed-width column layout for tabular command output (`ps`, `top`).
///
/// Cells are padded or truncated to their column width. In interactive mode
/// the header row is bold; plain and pipe modes emit no escape sequences.
package struct TableFormat: Sendable, Equatable {
    package struct Column: Sendable, Equatable {
        package let title: String
        package let width: Int
        package let alignment: TerminalLayout.Alignment

        package init(
            title: String,
            width: Int,
            alignment: TerminalLayout.Alignment = .left
        ) {
            self.title = title
            self.width = width
            self.alignment = alignment
        }
    }

    package let columns: [Column]
    package let columnGap: Int

    private static let bold = "\u{001B}[1m"
    private static let reset = "\u{001B}[0m"

    package init(columns: [Column], columnGap: Int = 2) {
        self.columns = columns
        self.columnGap = columnGap
    }

    package func formatHeader(mode: TerminalMode) -> String {
        let line = joinedCells(columns.map(\.title))
        switch mode {
        case .interactive:
            return Self.bold + line + Self.reset
        case .plain, .pipe:
            return line
        }
    }

    package func formatRow(_ values: [String]) -> String {
        precondition(values.count == columns.count, "row has \(values.count) values for \(columns.count) columns")
        return joinedCells(values)
    }

    private func joinedCells(_ values: [String]) -> String {
        let gap = String(repeating: " ", count: columnGap)
        return zip(values, columns)
            .map { TerminalLayout.fit($0, width: $1.width, alignment: $1.alignment) }
            .joined(separator: gap)
    }
}
