import Foundation
import TerminalProgress

/// Streams image pull status to stderr without interleaving concurrent pull updates.
package actor ImagePullProgress {
    private let display: ProgressDisplay
    private let renderer: StackedProgressRenderer
    private let pipeOutput: Bool

    private var references: [String] = []
    private var states: [String: ImagePullState] = [:]
    private var pipeItemCounts: [String: Int] = [:]
    private var completedPipeLines: Set<String> = []
    private var prefixWidth = ANSIPrefix.defaultWidth

    private var formatMode: TerminalMode {
        display == .interactive ? .interactive : .plain
    }

    package init(
        display: ProgressDisplay,
        pipeOutput: Bool = false,
        write: @escaping @Sendable (String) -> Void = { fputs($0, stderr) }
    ) {
        self.display = display
        self.pipeOutput = pipeOutput
        self.renderer = StackedProgressRenderer(display: display, write: write)
    }

    package func begin(references: [String]) async {
        guard display != .silent, !references.isEmpty else { return }
        self.references = references
        states = Dictionary(references.map { ($0, ImagePullState()) }, uniquingKeysWith: { first, _ in first })
        pipeItemCounts = Dictionary(references.map { ($0, 0) }, uniquingKeysWith: { first, _ in first })
        prefixWidth = max(ANSIPrefix.defaultWidth, references.map(\.count).max() ?? 0)

        if pipeOutput {
            await renderer.begin(keys: references, lineProvider: {
                await self.currentLines()
            })
        } else {
            await renderer.begin(keys: references, lineProvider: {
                await self.currentLines()
            }, plainBootstrap: {
                await self.currentLines()
            })
        }
    }

    package func handler(for reference: String) -> ProgressUpdateHandler? {
        guard display != .silent else { return nil }
        return { events in
            await self.apply(events, to: reference)
        }
    }

    package func apply(_ events: [ProgressUpdateEvent], to reference: String) async {
        guard display != .silent, states[reference] != nil else { return }
        states[reference]?.apply(events)
        await emitUpdate(for: reference)
    }

    package func markComplete(reference: String, succeeded: Bool) async {
        guard display != .silent, states[reference] != nil else { return }
        states[reference]?.phase = succeeded ? .complete : .failed
        await emitUpdate(for: reference, forceCompletion: pipeOutput)
    }

    package func finish() async {
        await renderer.finishInteractive()
    }

    private func emitUpdate(for reference: String, forceCompletion: Bool = false) async {
        switch display {
        case .plain:
            if pipeOutput {
                if forceCompletion {
                    await writePipeCompletion(reference: reference)
                } else {
                    await writePipeItemUpdates(reference: reference)
                }
            } else {
                await renderer.writePlain(await line(for: reference))
            }
        case .interactive:
            await renderer.refreshInteractive()
        case .silent:
            break
        }
    }

    private func line(for reference: String) async -> String {
        let spinnerFrame = await renderer.interactiveSpinnerFrame
        return ImagePullFormat.statusLine(
            reference: reference,
            state: states[reference] ?? ImagePullState(),
            mode: formatMode,
            width: prefixWidth,
            spinnerFrame: spinnerFrame
        )
    }

    private func currentLines() async -> [String] {
        var lines: [String] = []
        for reference in references {
            lines.append(await line(for: reference))
        }
        return lines
    }

    private func writePipeCompletion(reference: String) async {
        guard !completedPipeLines.contains(reference) else { return }
        completedPipeLines.insert(reference)
        await renderer.writePlain(ImagePullFormat.completionLine(
            reference: reference,
            state: states[reference] ?? ImagePullState(phase: .complete),
            width: prefixWidth
        ))
    }

    private func writePipeItemUpdates(reference: String) async {
        guard states[reference]?.phase == .fetching else { return }
        let currentItems = states[reference]?.items ?? 0
        let lastItems = pipeItemCounts[reference] ?? 0
        guard currentItems > lastItems else { return }
        pipeItemCounts[reference] = currentItems
        await renderer.writePlain(await line(for: reference))
    }
}
