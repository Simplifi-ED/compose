import Foundation

/// Shared in-place stderr renderer for stacked compose progress lines (waves, image pulls).
package actor StackedProgressRenderer {
    private static let tickInterval: Duration = .milliseconds(100)

    private let display: ProgressDisplay
    private let write: @Sendable (String) -> Void

    private var keys: [String] = []
    private var prefixWidth = ANSIPrefix.defaultWidth
    private var inPlaceWriter = InPlaceTerminalWriter()
    private var spinnerIndex = 0
    private var ticker: Task<Void, Never>?
    private var lineProvider: (@Sendable () async -> [String])?

    package var interactiveSpinnerFrame: String {
        ProgressFormat.spinnerFrames[spinnerIndex % ProgressFormat.spinnerFrames.count]
    }

    package init(
        display: ProgressDisplay,
        write: @escaping @Sendable (String) -> Void = { fputs($0, stderr) }
    ) {
        self.display = display
        self.write = write
    }

    package func begin(
        keys: [String],
        lineProvider: @escaping @Sendable () async -> [String],
        plainBootstrap: (@Sendable () async -> [String])? = nil
    ) async {
        guard display != .silent, !keys.isEmpty else { return }
        self.keys = keys
        self.lineProvider = lineProvider
        prefixWidth = max(ANSIPrefix.defaultWidth, keys.map(\.count).max() ?? 0)
        inPlaceWriter.reset()

        switch display {
        case .plain:
            if let plainBootstrap {
                for line in await plainBootstrap() {
                    writePlain(line)
                }
            }
        case .interactive:
            await refreshInteractive()
            startTicker()
        case .silent:
            break
        }
    }

    package func writePlain(_ line: String) {
        guard display == .plain else { return }
        write(line + "\n")
    }

    package func refreshInteractive() async {
        guard display == .interactive, let lineProvider else { return }
        let lines = await lineProvider()
        var output = inPlaceWriter.beginRedraw(newLineCount: lines.count)
        for line in lines {
            output += InPlaceTerminalWriter.formattedLine(line)
        }
        inPlaceWriter.commit(lineCount: lines.count)
        write(output)
    }

    package func finishInteractive() async {
        stopTicker()
        guard display == .interactive else { return }
        if !keys.isEmpty {
            await refreshInteractive()
        }
        keys = []
        lineProvider = nil
        inPlaceWriter.reset()
    }

    private func startTicker() {
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.tickInterval)
                await self?.tick()
            }
        }
    }

    private func tick() async {
        guard display == .interactive else { return }
        spinnerIndex += 1
        await refreshInteractive()
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }
}
