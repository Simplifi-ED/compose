import Foundation

/// Stable per-service log prefix: `web    | `.
///
/// The service name is left-aligned in a fixed width followed by `| `.
/// In interactive mode the name is colored with a deterministic hash so a
/// service keeps the same color across runs; plain and pipe modes emit the
/// same visible text without escape sequences.
package enum ANSIPrefix {
    package static let defaultWidth = 8

    /// Standard ANSI foreground colors (regular + bright), skipping hard-to-read codes.
    private static let palette: [Int] = [31, 32, 33, 34, 35, 36, 91, 92, 93, 94, 95, 96]

    private static let reset = "\u{001B}[0m"

    package static func format(
        serviceName: String,
        mode: TerminalMode,
        width: Int = defaultWidth
    ) -> String {
        let fitted = fit(serviceName, width: width)
        let padded = fitted.padding(toLength: max(width, fitted.count), withPad: " ", startingAt: 0)
        switch mode {
        case .interactive:
            let color = palette[colorIndex(for: serviceName)]
            return "\u{001B}[\(color)m\(padded)\(reset)| "
        case .plain, .pipe:
            return "\(padded)| "
        }
    }

    /// Deterministic palette index for a service name (FNV-1a over UTF-8 bytes).
    package static func colorIndex(for serviceName: String) -> Int {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in serviceName.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return Int(hash % UInt64(palette.count))
    }

    /// Truncates names longer than `width` to `width - 1` characters plus an ellipsis.
    private static func fit(_ name: String, width: Int) -> String {
        guard name.count > width else { return name }
        return String(name.prefix(max(width - 1, 0))) + "…"
    }
}
