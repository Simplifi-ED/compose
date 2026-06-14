import ComposeCore
import ContainerResource
import Foundation

extension TestRunner {
    mutating func runEventsTests() {
        runProjectEventsDiffTests()
        runProjectEventFormatTests()
        runProjectEventsSessionTests()
        runProjectEventsPollingEmitTests()
    }

    private mutating func runProjectEventsDiffTests() {
        let empty: [String: RuntimeStatus] = [:]

        let firstStart = ProjectEventsDiff.transitions(
            previous: empty,
            current: ["demo_web_1": .running]
        )
        expect(firstStart.count == 1, "new running container emits start")
        expect(firstStart[0].kind == .start, "first transition is start")
        expect(firstStart[0].containerID == "demo_web_1", "start names container id")

        let dieOnStop = ProjectEventsDiff.transitions(
            previous: ["demo_web_1": .running],
            current: ["demo_web_1": .stopped]
        )
        expect(dieOnStop.count == 1, "running to stopped emits die")
        expect(dieOnStop[0].kind == .die, "stop transition is die")

        let dieOnRemove = ProjectEventsDiff.transitions(
            previous: ["demo_web_1": .running],
            current: [:]
        )
        expect(dieOnRemove.count == 1, "removed container emits die")
        expect(dieOnRemove[0].kind == .die, "removal transition is die")

        let restart = ProjectEventsDiff.transitions(
            previous: ["demo_web_1": .stopped],
            current: ["demo_web_1": .running]
        )
        expect(restart.count == 1, "stopped to running emits start")
        expect(restart[0].kind == .start, "restart transition is start")

        let unknownToRunning = ProjectEventsDiff.transitions(
            previous: ["demo_web_1": .unknown],
            current: ["demo_web_1": .running]
        )
        expect(unknownToRunning.count == 1, "unknown to running emits start")
        expect(unknownToRunning[0].kind == .start, "unknown transition is start")

        let steady = ProjectEventsDiff.transitions(
            previous: ["demo_web_1": .running],
            current: ["demo_web_1": .running]
        )
        expect(steady.isEmpty, "unchanged running emits nothing")

        let snapshot = ProjectEventsDiff.snapshotStarts(
            current: ["demo_web_1": .running, "demo_db_1": .stopped]
        )
        expect(snapshot.count == 1, "snapshot mode reports running only")
        expect(snapshot[0].containerID == "demo_web_1", "snapshot start id")
    }

    private mutating func runProjectEventFormatTests() {
        let transition = ProjectEventTransition(
            kind: .start,
            containerID: "demo_web_1",
            containerName: "demo_web_1"
        )
        let timestamp = Date(timeIntervalSince1970: 0)
        let line = ProjectEventFormat.formatLine(transition: transition, timestamp: timestamp)
        expect(line.hasPrefix("["), "event line starts with timestamp bracket")
        expect(line.contains("container start demo_web_1 (demo_web_1)"), "event line includes action and names")
        expect(line.hasSuffix("\n"), "event line ends with newline")
        expect(!line.contains("\u{001B}"), "event line has no ANSI escapes")
    }

    private mutating func runProjectEventsSessionTests() {
        runProjectEventsClientSessionEndTests()
        runProjectEventsTimeoutTests()
    }

    private mutating func runProjectEventsClientSessionEndTests() {
        var session = ContainerListClientSession(machineContext: .applicationSandbox)
        expect(!session.isEnded, "new session is active")
        session.end()
        expect(session.isEnded, "end() marks session closed")
    }

    private mutating func runProjectEventsTimeoutTests() {
        let options = ProjectEventsOptions(
            projectName: "demo",
            serviceFilter: nil,
            machineContext: .applicationSandbox,
            follow: true,
            timeout: .milliseconds(50),
            pollInterval: .milliseconds(10)
        )
        let started = ContinuousClock.now
        blockingAwait {
            var session = ContainerListClientSession(machineContext: .applicationSandbox)
            defer { session.end() }
            try? await ProjectEventsSession.runPolling(
                options: options,
                session: &session,
                listProject: { _, _ in [] }
            )
        }
        let elapsed = started.duration(to: ContinuousClock.now)
        expect(elapsed >= .milliseconds(40), "idle follow respects timeout window")
        expect(elapsed < .seconds(2), "idle follow exits without hanging")
    }

    private mutating func runProjectEventsPollingEmitTests() {
        let options = ProjectEventsOptions(
            projectName: "demo",
            serviceFilter: nil,
            machineContext: .applicationSandbox,
            follow: false
        )
        final class Capture: @unchecked Sendable {
            var emitted: [ProjectEventTransition] = []
        }
        let capture = Capture()
        blockingAwait {
            var session = ContainerListClientSession(machineContext: .applicationSandbox)
            defer { session.end() }
            try? await ProjectEventsSession.runPolling(
                options: options,
                session: &session,
                listProject: { _, _ in
                    [
                        ProjectContainer(
                            name: "demo_web_1",
                            serviceName: "web",
                            status: .running,
                            publishedPorts: []
                        )
                    ]
                },
                emit: { transition in
                    capture.emitted.append(transition)
                }
            )
        }
        expect(capture.emitted.count == 1, "snapshot poll emits one start")
        expect(capture.emitted[0].kind == .start, "snapshot event is start")
        expect(capture.emitted[0].containerID == "demo_web_1", "snapshot event names container")
    }
}
