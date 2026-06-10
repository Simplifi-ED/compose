import Darwin
import Foundation

/// Low-level stdout/stderr preparation for streaming observability commands.
package enum TerminalOutput {
    /// Disables stdio buffering so tables and log lines flush immediately.
    package static func prepareStdout() {
        fflush(stdout)
        setbuf(stdout, nil)
    }
}
