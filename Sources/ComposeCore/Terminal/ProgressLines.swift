import Foundation

/// Streams per-service orchestration status to stderr during `up`/`down` waves.
///
/// All writes are funneled through this actor so parallel service completions
/// cannot interleave escape sequences. Image pulls inside `ContainerRun` may emit
/// their own progress; `--progress none` silences orchestration lines if the two
/// ever stack.
package actor ProgressLines {
    private static let tickInterval: Duration = .milliseconds(100)

    private let display: ProgressDisplay
    private let phase: ProgressPhase
    private let write: @Sendable (String) -> Void

    private var services: [String] = []
    private var statuses: [String: ProgressStatus] = [:]
    private var prefixWidth = ANSIPrefix.defaultWidth
    private var inPlaceWriter = InPlaceTerminalWriter()
    private var spinnerIndex = 0
    private var ticker: Task<Void, Never>?

    private var formatMode: TerminalMode {
        display == .interactive ? .interactive : .plain
    }

    package init(
        display: ProgressDisplay,
        phase: ProgressPhase,
        write: @escaping @Sendable (String) -> Void = { fputs($0, stderr) }
    ) {
        self.display = display
        self.phase = phase
        self.write = write
    }

    package func beginWave(wave: Int, total: Int, services: [String]) {
        guard display != .silent else { return }
        self.services = services
        statuses = Dictionary(services.map { ($0, ProgressStatus.inProgress) }, uniquingKeysWith: { first, _ in first })
        prefixWidth = max(ANSIPrefix.defaultWidth, services.map(\.count).max() ?? 0)
        inPlaceWriter.reset()

        switch display {
        case .plain:
            if total > 1 {
                write(ProgressFormat.waveHeader(wave: wave, total: total) + "\n")
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
        let status: ProgressStatus = succeeded ? .succeeded : .failed
        statuses[service] = status

        switch display {
        case .plain:
            write(line(for: service, status: status) + "\n")
        case .interactive:
            render()
            if statuses.values.allSatisfy({ $0 != .inProgress }) {
                stopTicker()
            }
        case .silent:
            break
        }
    }

    /// Stops the spinner and leaves the final per-service lines in place.
    package func finishWave() {
        guard display == .interactive else { return }
        stopTicker()
        render()
        resetState()
    }

    /// Stops any in-flight rendering; safe to call after success or failure.
    package func finish() {
        finishWave()
    }

    private func line(for service: String, status: ProgressStatus) -> String {
        ProgressFormat.statusLine(
            service: service,
            status: status,
            phase: phase,
            mode: formatMode,
            width: prefixWidth,
            spinnerFrame: ProgressFormat.spinnerFrames[spinnerIndex % ProgressFormat.spinnerFrames.count]
        )
    }

    private func render() {
        var output = inPlaceWriter.beginRedraw(newLineCount: services.count)
        for service in services {
            output += InPlaceTerminalWriter.formattedLine(
                line(for: service, status: statuses[service] ?? .inProgress)
            )
        }
        inPlaceWriter.commit(lineCount: services.count)
        write(output)
    }

    private func resetState() {
        services = []
        statuses = [:]
        inPlaceWriter.reset()
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
