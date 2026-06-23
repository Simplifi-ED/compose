import Foundation

package enum ProgressPhase: Sendable {
    case starting
    case stopping
}

package enum ProgressStatus: Equatable, Sendable {
    case inProgress
    case succeeded
    case failed
}

/// Pure formatters for orchestration progress lines (verified by compose-verify).
package enum ProgressMarkState: Equatable, Sendable {
    case inProgress(spinnerFrame: String)
    case succeeded
    case failed
}

package enum ProgressFormat {
    package static let spinnerFrames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

    package static func mark(for state: ProgressMarkState) -> String {
        switch state {
        case .inProgress(let spinnerFrame):
            return spinnerFrame
        case .succeeded:
            return "\u{001B}[32m✔\u{001B}[0m"
        case .failed:
            return "\u{001B}[31m✖\u{001B}[0m"
        }
    }

    package static func waveHeader(wave: Int, total: Int) -> String {
        "Wave \(wave) of \(total)"
    }

    package static func statusLine(
        service: String,
        status: ProgressStatus,
        phase: ProgressPhase,
        mode: TerminalMode,
        width: Int = ANSIPrefix.defaultWidth,
        spinnerFrame: String = spinnerFrames[0]
    ) -> String {
        let verb = verb(for: status, phase: phase)
        switch mode {
        case .interactive:
            let markState: ProgressMarkState = switch status {
            case .inProgress:
                .inProgress(spinnerFrame: spinnerFrame)
            case .succeeded:
                .succeeded
            case .failed:
                .failed
            }
            let mark = mark(for: markState)
            return "\(mark) \(ANSIPrefix.format(serviceName: service, mode: .interactive, width: width))\(verb)"
        case .plain, .pipe:
            return "\(ANSIPrefix.format(serviceName: service, mode: .plain, width: width))\(verb)"
        }
    }

    package static func verb(for status: ProgressStatus, phase: ProgressPhase) -> String {
        switch (phase, status) {
        case (.starting, .inProgress):
            return "Starting"
        case (.starting, .succeeded):
            return "Started"
        case (.stopping, .inProgress):
            return "Stopping"
        case (.stopping, .succeeded):
            return "Stopped"
        case (_, .failed):
            return "Failed"
        }
    }
}
