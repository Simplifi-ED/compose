import ComposeCore
import Foundation

extension TestRunner {
    mutating func runProgressTests() {
        runProgressDisplayResolutionTests()
        runProgressLineFormatTests()
        runProgressPlainOutputTests()
        runProgressSilentOutputTests()
        runProgressWaveHandlerTests()
    }

    private mutating func runProgressDisplayResolutionTests() {
        expect(
            ProgressDisplay.resolve(setting: .none, isTTY: true, environment: [:]) == .silent,
            "--progress none resolves silent even on a TTY"
        )
        expect(
            ProgressDisplay.resolve(setting: .plain, isTTY: true, environment: [:]) == .plain,
            "--progress plain forces plain on a TTY"
        )
        expect(
            ProgressDisplay.resolve(setting: .auto, isTTY: false, environment: [:]) == .plain,
            "auto on non-TTY stderr resolves plain"
        )
        expect(
            ProgressDisplay.resolve(setting: .auto, isTTY: true, environment: ["NO_COLOR": "1"]) == .plain,
            "auto with NO_COLOR resolves plain"
        )
        expect(
            ProgressDisplay.resolve(setting: .auto, isTTY: true, environment: ["CI": "true"]) == .plain,
            "auto in CI resolves plain"
        )
        expect(
            ProgressDisplay.resolve(setting: .auto, isTTY: true, environment: [:]) == .interactive,
            "auto on a clean TTY resolves interactive"
        )
    }

    private mutating func runProgressLineFormatTests() {
        expect(
            ProgressLines.waveHeader(wave: 1, total: 2) == "Wave 1 of 2",
            "wave header format"
        )

        let starting = ProgressLines.statusLine(
            service: "web", status: .inProgress, phase: .starting, display: .plain
        )
        expect(starting == "web     | Starting", "plain starting line")
        expect(!starting.contains("\u{001B}["), "plain line has no escape sequences")

        expect(
            ProgressLines.statusLine(service: "web", status: .succeeded, phase: .starting, display: .plain)
                == "web     | Started",
            "plain started line"
        )
        expect(
            ProgressLines.statusLine(service: "web", status: .failed, phase: .starting, display: .plain)
                == "web     | Failed",
            "plain failed line"
        )
        expect(
            ProgressLines.statusLine(service: "db", status: .inProgress, phase: .stopping, display: .plain)
                == "db      | Stopping",
            "plain stopping line"
        )
        expect(
            ProgressLines.statusLine(service: "db", status: .succeeded, phase: .stopping, display: .plain)
                == "db      | Stopped",
            "plain stopped line"
        )

        let interactive = ProgressLines.statusLine(
            service: "web", status: .succeeded, phase: .starting, display: .interactive
        )
        expect(interactive.contains("\u{001B}["), "interactive line contains escape sequences")
        expect(
            stripANSI(interactive) == "✔ web     | Started",
            "interactive line matches plain shape once ANSI is stripped"
        )

        let spinning = ProgressLines.statusLine(
            service: "web", status: .inProgress, phase: .starting, display: .interactive, spinnerFrame: "⠙"
        )
        expect(stripANSI(spinning) == "⠙ web     | Starting", "interactive in-progress line shows spinner frame")

        let wide = ProgressLines.statusLine(
            service: "longservicename", status: .succeeded, phase: .starting, display: .plain, width: 15
        )
        expect(wide == "longservicename| Started", "custom width avoids truncating long service names")
    }

    private mutating func runProgressPlainOutputTests() {
        let buffer = LineBuffer()
        blockingAwait {
            let lines = ProgressLines(display: .plain, phase: .starting) { buffer.append($0) }
            await lines.beginWave(wave: 1, total: 2, services: ["db", "web"])
            await lines.markComplete(service: "db", succeeded: true)
            await lines.markComplete(service: "web", succeeded: false)
            await lines.finishWave()
            await lines.finish()
        }

        let output = buffer.lines
        expect(
            output == [
                "Wave 1 of 2\n",
                "db      | Starting\n",
                "web     | Starting\n",
                "db      | Started\n",
                "web     | Failed\n"
            ],
            "plain mode emits wave header then one line per state change"
        )
        expect(
            !output.joined().contains("\u{001B}["),
            "plain mode never writes escape sequences"
        )

        let singleWave = LineBuffer()
        blockingAwait {
            let lines = ProgressLines(display: .plain, phase: .stopping) { singleWave.append($0) }
            await lines.beginWave(wave: 1, total: 1, services: ["web"])
            await lines.markComplete(service: "web", succeeded: true)
        }
        expect(
            singleWave.lines == ["web     | Stopping\n", "web     | Stopped\n"],
            "single-wave plain output skips the wave header"
        )
    }

    private mutating func runProgressSilentOutputTests() {
        let buffer = LineBuffer()
        blockingAwait {
            let lines = ProgressLines(display: .silent, phase: .starting) { buffer.append($0) }
            await lines.beginWave(wave: 1, total: 1, services: ["web"])
            await lines.markComplete(service: "web", succeeded: true)
            await lines.finishWave()
            await lines.finish()
        }
        expect(buffer.lines.isEmpty, "silent mode writes nothing")
    }

    /// Empty layers exercise wave callbacks without touching the container runtime.
    private mutating func runProgressWaveHandlerTests() {
        let events = LineBuffer()
        let handlers = WaveProgressHandlers(
            onWaveStart: { wave, total, services in
                events.append("start \(wave)/\(total) services=\(services.count)")
            },
            onServiceComplete: { service, succeeded in
                events.append("complete \(service) \(succeeded)")
            },
            onWaveComplete: { wave in
                events.append("done \(wave)")
            }
        )
        blockingAwait {
            try? await ServiceRunner.down(layers: [[], []], progress: handlers)
        }
        expect(
            events.lines == ["start 1/2 services=0", "done 1", "start 2/2 services=0", "done 2"],
            "wave callbacks fire in order around each wave"
        )
    }
}
