import ContainerAPIClient
import ContainerizationOS
import Foundation
import Logging

extension TestRunner {
    mutating func runTerminalResizeTests() {
        runTerminalResizeLoopTests()
    }

    private mutating func runTerminalResizeLoopTests() {
        let initialSize = Terminal.Size(width: 80, height: 24)
        let resized = Terminal.Size(width: 100, height: 30)
        let outcome = blockingAwait { () -> ResizeLoopOutcome in
            let process = RecordingMockClientProcess(exitCode: 0)
            let (stream, continuation) = AsyncStream<Void>.makeStream()
            let sizeSequence = ResizeSizeSequence(sizes: [initialSize, resized])
            let log = Logger(label: "compose-verify.terminal-resize")

            let loop = Task {
                await TerminalResizeLoopTestSupport.applyInitialAndForward(
                    process: process,
                    currentSize: { sizeSequence.next() },
                    winchEvents: stream,
                    log: log
                )
            }

            await Task.yield()
            continuation.yield(())
            continuation.finish()
            await loop.value
            let calls = await process.resizeCalls
            return ResizeLoopOutcome(count: calls.count, first: calls.first, last: calls.last)
        }

        expect(outcome.count == 2, "terminal resize loop applies initial size and one WINCH resize")
        expect(outcome.first?.width == initialSize.width, "initial resize uses starting terminal width")
        expect(outcome.first?.height == initialSize.height, "initial resize uses starting terminal height")
        expect(outcome.last?.width == resized.width, "WINCH resize uses updated terminal width")
        expect(outcome.last?.height == resized.height, "WINCH resize uses updated terminal height")
    }
}

private struct ResizeLoopOutcome: Sendable {
    let count: Int
    let first: Terminal.Size?
    let last: Terminal.Size?
}

/// Mirrors upstream `ProcessIO.handleProcess` WINCH forwarding for compose-verify only.
private enum TerminalResizeLoopTestSupport {
    static func applyInitialAndForward(
        process: any ClientProcess,
        currentSize: @Sendable () throws -> Terminal.Size,
        winchEvents: AsyncStream<Void>,
        log: Logger
    ) async {
        try? await process.resize(try currentSize())
        for await _ in winchEvents {
            do {
                try await process.resize(try currentSize())
            } catch {
                log.error(
                    "failed to send terminal resize event",
                    metadata: [
                        "error": "\(error)"
                    ]
                )
            }
        }
    }
}

private final class ResizeSizeSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var index = 0
    private let sizes: [Terminal.Size]

    init(sizes: [Terminal.Size]) {
        self.sizes = sizes
    }

    func next() -> Terminal.Size {
        lock.lock()
        defer { lock.unlock() }
        let value = sizes[min(index, sizes.count - 1)]
        index += 1
        return value
    }
}
