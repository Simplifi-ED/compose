import Foundation

/// Cursor-up, clear-line prefix used by interactive observability output (`top`, `up`/`down` progress).
package struct InPlaceTerminalWriter: Sendable {
    package private(set) var renderedLineCount = 0

    package init(renderedLineCount: Int = 0) {
        self.renderedLineCount = renderedLineCount
    }

    /// Escape prefix to reposition the cursor before rewriting `newLineCount` lines.
    package mutating func beginRedraw(newLineCount: Int) -> String {
        Self.redrawPrefix(previousLineCount: renderedLineCount, newLineCount: newLineCount)
    }

    package static func redrawPrefix(previousLineCount: Int, newLineCount: Int) -> String {
        var output = ""
        if previousLineCount > newLineCount {
            let extra = previousLineCount - newLineCount
            for _ in 0..<extra {
                output += clearLine() + "\n"
            }
        }
        if previousLineCount > 0 {
            output += "\u{001B}[\(previousLineCount)A"
        }
        return output
    }

    package static func clearLine() -> String {
        "\r\u{001B}[K"
    }

    package static func formattedLine(_ content: String) -> String {
        clearLine() + content + "\n"
    }

    package mutating func commit(lineCount: Int) {
        renderedLineCount = lineCount
    }

    package mutating func reset() {
        renderedLineCount = 0
    }
}
