import ArgumentParser
import ComposeCore
import ContainerResource
import Foundation

extension TestRunner {
    mutating func runAttachTests() throws {
        try runMakeLogSourcesFromPlansTests()
        runContainerExitWatchTests()
        runAttachBodyCompletionTests()
        runAttachMultiplexErrorTests()
        runAttachInterruptPolicyTests()
    }

    private mutating func runMakeLogSourcesFromPlansTests() throws {
        let composeFile = try ComposeParser.parse(fileURL: Self.fixtureURL("depends-compose.yml"))
        let composeDirectory = Self.fixtureURL("depends-compose.yml").deletingLastPathComponent()
        let plans = try ServicePlanner.plans(
            for: composeFile,
            projectName: "demo",
            composeDirectory: composeDirectory
        )
        let sources = makeLogSources(from: plans)
        expect(sources.count == plans.count, "plan log source count")
        expect(sources.allSatisfy { !$0.containerName.isEmpty }, "plan log source container names")
        expect(sources.allSatisfy { !$0.serviceLabel.isEmpty }, "plan log source service labels")
    }

    private mutating func runContainerExitWatchTests() {
        let completed = blockingAwait {
            try? await ContainerExitWatch.waitUntilAllStopped(ids: [], pollInterval: .milliseconds(1))
            return true
        }
        expect(completed, "empty watch list completes immediately")

        let counter = ExitWatchTestCounter(sequence: [.running, .running, .stopped])
        let readCount = blockingAwait {
            try? await ContainerExitWatch.waitUntilAllStopped(
                ids: ["demo_web"],
                pollInterval: .milliseconds(1)
            ) { _ in
                await counter.next()
            }
            return await counter.readCount
        }
        expect(readCount == 3, "watch polls until stopped")
    }

    private mutating func runAttachBodyCompletionTests() {
        let completed = blockingAwait {
            try? await LogFollowSession.runMultiplexUntilParallelCompletes(
                sources: [],
                options: LogStreamOptions(
                    tail: nil,
                    follow: true,
                    boot: false,
                    mode: .plain
                ),
                parallelUntilComplete: {}
            )
            return true
        }
        expect(completed, "attach parallel session completes when exit watch finishes")
    }

    private mutating func runAttachMultiplexErrorTests() {
        enum TestError: Error { case boom }

        let completed = blockingAwait {
            try? await LogFollowSession.runMultiplexUntilParallelCompletes(
                sources: [],
                options: LogStreamOptions(
                    tail: nil,
                    follow: true,
                    boot: false,
                    mode: .plain
                ),
                multiplex: { _, _ in throw TestError.boom },
                parallelUntilComplete: {}
            )
            return true
        }
        expect(completed, "multiplex error does not fail attach when exit watch completes")
    }

    private mutating func runAttachInterruptPolicyTests() {
        let context = ProjectShutdownContext(
            projectName: "demo",
            composeFile: nil,
            fileURLs: nil,
            options: GracefulStopOptions()
        )
        let recorder = AttachStopRecorder()
        let outcome = blockingAwait {
            try? await SignalForwarding.interruptedOutcome(
                policy: .stopProject(context),
                signal: InterruptSignal(number: 2),
                stopProject: { _ in await recorder.markStopped() }
            )
        }
        let stopped = blockingAwait { await recorder.didStop }
        expect(outcome == .interrupted(InterruptSignal(number: 2)), "attach interrupt maps to signal exit")
        expect(stopped, "attach interrupt stops project containers")

        enum StopError: Error { case boom }
        let failedStop = blockingAwait {
            try? await SignalForwarding.interruptedOutcome(
                policy: .stopProject(context),
                signal: InterruptSignal(number: 2),
                stopProject: { _ in throw StopError.boom }
            )
        }
        expect(
            failedStop == .interrupted(InterruptSignal(number: 2)),
            "stopProject failure still maps to signal exit"
        )
    }
}

private actor AttachStopRecorder {
    private(set) var didStop = false

    func markStopped() {
        didStop = true
    }
}

private actor ExitWatchTestCounter {
    private let sequence: [RuntimeStatus]
    private(set) var readCount = 0

    init(sequence: [RuntimeStatus]) {
        self.sequence = sequence
    }

    func next() -> RuntimeStatus {
        let index = min(readCount, sequence.count - 1)
        readCount += 1
        return sequence[index]
    }
}
