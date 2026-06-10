import ComposeCore
import ContainerResource
import Foundation

extension TestRunner {
    mutating func runLogsTests() {
        runLogFormatTests()
        runLogLineAssemblerTests()
        runLogMultiplexerTests()
        runProjectStatusFilterTests()
    }

    private mutating func runLogFormatTests() {
        let plain = LogFormat.formatLine(service: "web", line: "hello", mode: .plain, width: 8)
        expect(plain == "web     | hello\n", "plain log line includes padded prefix and newline")

        let interactive = LogFormat.formatLine(service: "web", line: "hello", mode: .interactive, width: 8)
        expect(interactive.contains("\u{001B}["), "interactive log line contains escape sequence")
        expect(stripANSI(interactive) == plain, "interactive log line matches plain once ANSI is stripped")

        let wide = LogFormat.formatLine(service: "db", line: "ready", mode: .plain, width: 4)
        expect(wide == "db  | ready\n", "custom width applies to log prefix")
    }

    private mutating func runLogLineAssemblerTests() {
        var assembler = LogLineAssembler()
        expect(assembler.append("a\nb") == ["a"], "assembler emits first complete line")
        expect(assembler.append("\nc") == ["b"], "assembler emits buffered line when newline arrives")
        expect(assembler.append("\n") == ["c"], "assembler emits subsequent complete line")
        expect(assembler.append("") == [], "empty chunk emits nothing")
        expect(assembler.append("hel") == [], "partial line stays buffered")
        expect(assembler.append("lo\n") == ["hello"], "partial line completes on next chunk")
        expect(assembler.finish() == [], "finish with no pending returns empty")
        expect(assembler.append("tail") == [], "trailing text without newline stays pending")
        expect(assembler.finish() == ["tail"], "finish flushes trailing text")
    }

    private mutating func runLogMultiplexerTests() {
        runLogMultiplexerInterleaveTests()
        runLogMultiplexerWidthTests()
        runLogMultiplexerPipeModeTests()
        runProjectStatusFilterTests()
    }

    private mutating func runLogMultiplexerInterleaveTests() {
        let buffer = LineBuffer()
        blockingAwait {
            let options = LogStreamOptions(tail: nil, follow: false, boot: false, mode: .plain)
            let mux = LogMultiplexer(serviceLabels: ["web", "db"], options: options) { buffer.append($0) }
            await mux.ingest(service: "web", chunk: "hello\nwo")
            await mux.ingest(service: "db", chunk: "SELECT\n")
            await mux.ingest(service: "web", chunk: "rld\n")
            await mux.finishPending(service: "web")
            await mux.finishPending(service: "db")
        }

        let output = buffer.lines.joined()
        let lines = output.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        expect(lines.count == 3, "interleaved ingest emits three lines")
        expect(lines.contains("web     | hello"), "interleaved output includes web hello line")
        expect(lines.contains("db      | SELECT"), "interleaved output includes db line")
        expect(lines.contains("web     | world"), "partial chunks reassemble to world")
    }

    private mutating func runLogMultiplexerWidthTests() {
        let buffer = LineBuffer()
        blockingAwait {
            let options = LogStreamOptions(tail: nil, follow: false, boot: false, mode: .plain)
            let mux = LogMultiplexer(
                serviceLabels: ["web", "verylongname"],
                options: options
            ) { buffer.append($0) }
            await mux.emit(service: "verylongname", line: "ok")
        }

        let line = buffer.lines.joined().trimmingCharacters(in: .newlines)
        expect(line == "verylongname| ok", "prefix width expands to longest service label")
    }

    private mutating func runLogMultiplexerPipeModeTests() {
        let buffer = LineBuffer()
        blockingAwait {
            let options = LogStreamOptions(tail: nil, follow: false, boot: false, mode: .pipe)
            let mux = LogMultiplexer(serviceLabels: ["web"], options: options) { buffer.append($0) }
            await mux.emit(service: "web", line: "piped")
        }

        let output = buffer.lines.joined()
        expect(!output.contains("\u{001B}["), "pipe mode log output has no escape sequences")
        expect(output == "web     | piped\n", "pipe mode log line matches plain formatting")
    }

    private mutating func runProjectStatusFilterTests() {
        let containers = [
            ProjectContainer(name: "demo_web", serviceName: "web", status: .running, publishedPorts: []),
            ProjectContainer(name: "demo_db", serviceName: "db", status: .running, publishedPorts: []),
            ProjectContainer(name: "legacy", serviceName: nil, status: .running, publishedPorts: [])
        ]

        let all = ProjectStatus.filteredContainers(from: containers, filter: nil)
        expect(all.count == 3, "no filter returns all project containers")

        let webOnly = ProjectStatus.filteredContainers(from: containers, filter: ["web"])
        expect(webOnly.count == 1, "service filter limits to matching label")
        expect(webOnly[0].serviceName == "web", "filtered container is web")

        let missing = ProjectStatus.filteredContainers(from: containers, filter: ["cache"])
        expect(missing.isEmpty, "unknown service filter returns empty list")
    }
}
