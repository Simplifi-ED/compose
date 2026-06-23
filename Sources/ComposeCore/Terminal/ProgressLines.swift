import Foundation

/// Streams per-service orchestration status to stderr during `up`/`down` waves.
///
/// All writes are funneled through this actor so parallel service completions
/// cannot interleave escape sequences. Compose-owned image pull progress finishes
/// before startup wave progress starts.
package actor ProgressLines {
    private let display: ProgressDisplay
    private let phase: ProgressPhase
    private let renderer: StackedProgressRenderer

    private var services: [String] = []
    private var statuses: [String: ProgressStatus] = [:]
    private var prefixWidth = ANSIPrefix.defaultWidth

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
        self.renderer = StackedProgressRenderer(display: display, write: write)
    }

    package func beginWave(wave: Int, total: Int, services: [String]) async {
        guard display != .silent else { return }
        self.services = services
        statuses = Dictionary(services.map { ($0, ProgressStatus.inProgress) }, uniquingKeysWith: { first, _ in first })
        prefixWidth = max(ANSIPrefix.defaultWidth, services.map(\.count).max() ?? 0)

        await renderer.begin(keys: services, lineProvider: {
            await self.currentLines()
        }, plainBootstrap: {
            var lines: [String] = []
            if total > 1 {
                lines.append(ProgressFormat.waveHeader(wave: wave, total: total))
            }
            for service in services {
                lines.append(await self.line(for: service, status: .inProgress))
            }
            return lines
        })
    }

    package func markComplete(service: String, succeeded: Bool) async {
        guard display != .silent, statuses[service] != nil else { return }
        let status: ProgressStatus = succeeded ? .succeeded : .failed
        statuses[service] = status

        switch display {
        case .plain:
            await renderer.writePlain(await line(for: service, status: status))
        case .interactive:
            await renderer.refreshInteractive()
            if statuses.values.allSatisfy({ $0 != .inProgress }) {
                await renderer.finishInteractive()
            }
        case .silent:
            break
        }
    }

    /// Stops the spinner and leaves the final per-service lines in place.
    package func finishWave() async {
        await renderer.finishInteractive()
        resetState()
    }

    /// Stops any in-flight rendering; safe to call after success or failure.
    package func finish() async {
        await finishWave()
    }

    private func line(for service: String, status: ProgressStatus) async -> String {
        let spinnerFrame = await renderer.interactiveSpinnerFrame
        return ProgressFormat.statusLine(
            service: service,
            status: status,
            phase: phase,
            mode: formatMode,
            width: prefixWidth,
            spinnerFrame: spinnerFrame
        )
    }

    private func currentLines() async -> [String] {
        var lines: [String] = []
        for service in services {
            lines.append(await line(for: service, status: statuses[service] ?? .inProgress))
        }
        return lines
    }

    private func resetState() {
        services = []
        statuses = [:]
    }
}
