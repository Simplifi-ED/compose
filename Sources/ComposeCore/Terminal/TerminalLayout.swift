import Foundation

/// Shared cell layout helpers for terminal output.
package enum TerminalLayout {
    package enum Alignment: Sendable {
        case left
        case right
    }

    /// Pads `string` to `width`, or truncates to `width - 1` characters plus an ellipsis.
    package static func fit(_ string: String, width: Int, alignment: Alignment = .left) -> String {
        precondition(width > 0, "column width must be positive")

        let cell: String
        if string.count > width {
            cell = String(string.prefix(max(width - 1, 0))) + "…"
        } else {
            cell = string
        }

        let pad = String(repeating: " ", count: max(width - cell.count, 0))
        switch alignment {
        case .left:
            return cell + pad
        case .right:
            return pad + cell
        }
    }
}
