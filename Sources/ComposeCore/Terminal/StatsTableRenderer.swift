import Foundation

/// Renders a stats table to stdout with cursor-up redraw in interactive mode.
package actor StatsTableRenderer {
    private let table: TableFormat
    private let mode: TerminalMode
    private let write: @Sendable (String) -> Void

    private var inPlaceWriter = InPlaceTerminalWriter()

    package init(
        table: TableFormat,
        mode: TerminalMode,
        write: @escaping @Sendable (String) -> Void = { print($0, terminator: "") }
    ) {
        self.table = table
        self.mode = mode
        self.write = write
    }

    package func render(rows: [ProjectStatsRow]) {
        switch mode {
        case .interactive:
            renderInteractive(rows: rows)
        case .plain, .pipe:
            renderPlain(rows: rows)
        }
    }

    package func finish() {
        inPlaceWriter.reset()
    }

    private func renderPlain(rows: [ProjectStatsRow]) {
        var output = table.formatHeader(mode: mode) + "\n"
        for row in rows {
            output += table.formatRow(row.cells) + "\n"
        }
        write(output)
    }

    private func renderInteractive(rows: [ProjectStatsRow]) {
        let lineCount = 1 + rows.count
        var output = inPlaceWriter.beginRedraw(newLineCount: lineCount)
        output += InPlaceTerminalWriter.formattedLine(table.formatHeader(mode: mode))
        for row in rows {
            output += InPlaceTerminalWriter.formattedLine(table.formatRow(row.cells))
        }
        inPlaceWriter.commit(lineCount: lineCount)
        write(output)
    }
}
