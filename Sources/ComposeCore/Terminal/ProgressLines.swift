import Foundation

/// User-selected `--progress` value before terminal detection.
package enum ProgressSetting: String, CaseIterable, Sendable {
    /// Detect from the standard error terminal (spinner on a TTY, plain text otherwise).
    case auto
    /// Newline-separated status lines without escape sequences.
    case plain
    /// No progress output.
    case none
}

/// Resolved rendering style for orchestration progress.
///
/// Progress renders on stderr, so `auto` resolves against the standard error
/// file descriptor rather than stdout (which carries container names).
package enum ProgressDisplay: Equatable, Sendable {
    /// stderr is a TTY with color allowed; spinner and in-place redraw.
    case interactive
    /// Newline-separated status lines; no escape sequences.
    case plain
    /// No progress output.
    case silent

    package static func resolve(
        setting: ProgressSetting,
        isTTY: Bool,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> ProgressDisplay {
        switch setting {
        case .none:
            return .silent
        case .plain:
            return .plain
        case .auto:
            guard isTTY else { return .plain }
            if TerminalMode.isEnvironmentColorDisabled(environment) || TerminalMode.isEnvironmentCI(environment) {
                return .plain
            }
            return .interactive
        }
    }

    /// Resolves against the live standard error file descriptor.
    package static func resolve(
        setting: ProgressSetting,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> ProgressDisplay {
        resolve(
            setting: setting,
            isTTY: isatty(FileHandle.standardError.fileDescriptor) == 1,
            environment: environment
        )
    }
}

/// Streams per-service orchestration status to stderr during `up`/`down` waves.
///
/// All writes are funneled through this actor so parallel service completions
/// cannot interleave escape sequences. Image pulls inside `ContainerRun` may emit
/// their own progress; `--progress none` silences orchestration lines if the two
/// ever stack.
package actor ProgressLines {
    package enum Phase: Sendable {
        case starting
        case stopping
    }

    package enum Status: Equatable, Sendable {
        case inProgress
        case succeeded
        case failed
    }

    private static let spinnerFrames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    private static let tickInterval: Duration = .milliseconds(100)

    private let display: ProgressDisplay
    private let phase: Phase
    private let write: @Sendable (String) -> Void

    private var services: [String] = []
    private var statuses: [String: Status] = [:]
    private var prefixWidth = ANSIPrefix.defaultWidth
    private var renderedLineCount = 0
    private var spinnerIndex = 0
    private var ticker: Task<Void, Never>?

    package init(
        display: ProgressDisplay,
        phase: Phase,
        write: @escaping @Sendable (String) -> Void = { fputs($0, stderr) }
    ) {
        self.display = display
        self.phase = phase
        self.write = write
    }

    package func beginWave(wave: Int, total: Int, services: [String]) {
        guard display != .silent else { return }
        self.services = services
        statuses = Dictionary(services.map { ($0, Status.inProgress) }, uniquingKeysWith: { first, _ in first })
        prefixWidth = max(ANSIPrefix.defaultWidth, services.map(\.count).max() ?? 0)
        renderedLineCount = 0

        switch display {
        case .plain:
            if total > 1 {
                write(Self.waveHeader(wave: wave, total: total) + "\n")
            }
            for service in services {
                write(line(for: service, status: .inProgress) + "\n")
            }
        case .interactive:
            render()
            startTicker()
        case .silent:
            break
        }
    }

    package func markComplete(service: String, succeeded: Bool) {
        guard display != .silent, statuses[service] != nil else { return }
        let status: Status = succeeded ? .succeeded : .failed
        statuses[service] = status

        switch display {
        case .plain:
            write(line(for: service, status: status) + "\n")
        case .interactive:
            render()
            // Once the wave is fully terminal, stop redrawing so later stderr
            // writers (rollback warnings, error output) are not overwritten.
            if statuses.values.allSatisfy({ $0 != .inProgress }) {
                stopTicker()
            }
        case .silent:
            break
        }
    }

    /// Stops the spinner and leaves the final per-service lines in place.
    /// Call before printing container names to stdout.
    package func finishWave() {
        guard display == .interactive else { return }
        stopTicker()
        render()
        services = []
        statuses = [:]
        renderedLineCount = 0
    }

    /// Stops any in-flight rendering; safe to call after success or failure.
    package func finish() {
        guard display == .interactive else { return }
        stopTicker()
        if !services.isEmpty {
            render()
            services = []
            statuses = [:]
            renderedLineCount = 0
        }
    }

    // MARK: - Pure formatting (verified by compose-verify)

    package static func waveHeader(wave: Int, total: Int) -> String {
        "Wave \(wave) of \(total)"
    }

    package static func statusLine(
        service: String,
        status: Status,
        phase: Phase,
        display: ProgressDisplay,
        width: Int = ANSIPrefix.defaultWidth,
        spinnerFrame: String = spinnerFrames[0]
    ) -> String {
        let verb = verb(for: status, phase: phase)
        switch display {
        case .interactive:
            let mark: String
            switch status {
            case .inProgress:
                mark = spinnerFrame
            case .succeeded:
                mark = "\u{001B}[32m✔\u{001B}[0m"
            case .failed:
                mark = "\u{001B}[31m✖\u{001B}[0m"
            }
            return "\(mark) \(ANSIPrefix.format(serviceName: service, mode: .interactive, width: width))\(verb)"
        case .plain, .silent:
            return "\(ANSIPrefix.format(serviceName: service, mode: .plain, width: width))\(verb)"
        }
    }

    package static func verb(for status: Status, phase: Phase) -> String {
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

    // MARK: - Interactive rendering

    private func line(for service: String, status: Status) -> String {
        Self.statusLine(
            service: service,
            status: status,
            phase: phase,
            display: display,
            width: prefixWidth,
            spinnerFrame: Self.spinnerFrames[spinnerIndex % Self.spinnerFrames.count]
        )
    }

    /// Redraws the whole wave block in place: cursor up over previously
    /// rendered lines, then one cleared-and-rewritten line per service.
    private func render() {
        var output = ""
        if renderedLineCount > 0 {
            output += "\u{001B}[\(renderedLineCount)A"
        }
        for service in services {
            output += "\r\u{001B}[K"
            output += line(for: service, status: statuses[service] ?? .inProgress)
            output += "\n"
        }
        renderedLineCount = services.count
        write(output)
    }

    private func startTicker() {
        stopTicker()
        ticker = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.tickInterval)
                guard !Task.isCancelled else { return }
                spinnerIndex += 1
                render()
            }
        }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }
}
