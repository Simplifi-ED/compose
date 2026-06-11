import ComposeCore
import ContainerizationError
import ContainerResource
import Foundation

extension TestRunner {
    mutating func runLogsTests() {
        runLogFormatTests()
        runLogLineAssemblerTests()
        runLogTailReaderTests()
        runLogMultiplexerTests()
        runProjectStatusFilterTests()
        runLogsExitPathTests()
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

    private mutating func runLogTailReaderTests() {
        runLogTailReaderSplitTests()
        runLogTailReaderFullReadTests()
        runLogTailReaderTailTests()
        runLogTailReaderUTF8BoundaryTests()
        runLogTailReaderErrorTests()
    }

    private mutating func runLogTailReaderSplitTests() {
        expect(LogTailReader.splitLogLines("") == [], "split on empty string is empty")
        expect(LogTailReader.splitLogLines("a") == ["a"], "split without newline is one line")
        expect(
            LogTailReader.splitLogLines("\n\nfirst\nsecond\n") == ["", "", "first", "second"],
            "split preserves leading blank lines"
        )
        expect(
            LogTailReader.splitLogLines("first\n\nsecond\n") == ["first", "", "second"],
            "split preserves interior blank lines"
        )
    }

    private mutating func runLogTailReaderFullReadTests() {
        do {
            let handle = try logFileHandle(with: "\n\nfirst\nsecond\n")
            defer { try? handle.close() }
            let lines = try LogTailReader.readLines(from: handle, tail: nil)
            expect(lines == ["", "", "first", "second"], "full read preserves leading blank lines")
        } catch {
            fputs("FAIL: full read test setup: \(error)\n", stderr)
            failures += 1
        }
    }

    private mutating func runLogTailReaderTailTests() {
        do {
            let handle = try logFileHandle(with: "alpha\n\nbeta\ngamma\n")
            defer { try? handle.close() }
            let lines = try LogTailReader.readLines(from: handle, tail: 3)
            expect(lines == ["", "beta", "gamma"], "tail count includes blank lines")
        } catch {
            fputs("FAIL: tail read test setup: \(error)\n", stderr)
            failures += 1
        }
    }

    private mutating func runLogTailReaderUTF8BoundaryTests() {
        do {
            let prefix = String(repeating: "x", count: 1023)
            let handle = try logFileHandle(with: "\(prefix)é\nvisible\n")
            defer { try? handle.close() }
            let lines = try LogTailReader.readLines(from: handle, tail: 1)
            expect(lines == ["visible"], "tail read decodes multibyte UTF-8 split across read boundary")
        } catch {
            fputs("FAIL: UTF-8 tail test setup: \(error)\n", stderr)
            failures += 1
        }
    }

    private mutating func runLogTailReaderErrorTests() {
        do {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("compose-verify-logs-\(UUID().uuidString).log")
            try Data([0xFF, 0xFE, 0x0A]).write(to: url)
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            expectThrows(ContainerizationError.self, "invalid utf8 log file") {
                _ = try LogTailReader.readLines(from: handle, tail: nil)
            }
        } catch {
            fputs("FAIL: invalid utf8 test setup: \(error)\n", stderr)
            failures += 1
        }
    }

    private func logFileHandle(with content: String) throws -> FileHandle {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("compose-verify-logs-\(UUID().uuidString).log")
        try content.write(to: url, atomically: true, encoding: .utf8)
        return try FileHandle(forReadingFrom: url)
    }

    private mutating func runLogMultiplexerTests() {
        runLogMultiplexerInterleaveTests()
        runLogMultiplexerReplicaTests()
        runLogSourceReplicaLabelTests()
        runLogMultiplexerWidthTests()
        runLogMultiplexerPipeModeTests()
    }

    private mutating func runLogSourceReplicaLabelTests() {
        let sources = makeLogSources(from: [
            (containerName: "demo_web_1", serviceName: "web"),
            (containerName: "demo_web_2", serviceName: "web"),
            (containerName: "demo_db_1", serviceName: "db")
        ])
        expect(sources[0].serviceLabel == "demo_web_1", "replica log prefix uses container name")
        expect(sources[1].serviceLabel == "demo_web_2", "second replica log prefix uses container name")
        expect(sources[2].serviceLabel == "db", "single replica keeps service label")
    }

    private mutating func runLogMultiplexerInterleaveTests() {
        let buffer = LineBuffer()
        blockingAwait {
            let options = LogStreamOptions(tail: nil, follow: false, boot: false, mode: .plain)
            let mux = LogMultiplexer(prefixLabels: ["web", "db"], options: options) { buffer.append($0) }
            await mux.ingest(container: "demo_web", prefix: "web", chunk: "hello\nwo")
            await mux.ingest(container: "demo_db", prefix: "db", chunk: "SELECT\n")
            await mux.ingest(container: "demo_web", prefix: "web", chunk: "rld\n")
            await mux.finishPending(container: "demo_web", prefix: "web")
            await mux.finishPending(container: "demo_db", prefix: "db")
        }

        let output = buffer.lines.joined()
        let lines = output.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        expect(lines.count == 3, "interleaved ingest emits three lines")
        expect(lines.contains("web     | hello"), "interleaved output includes web hello line")
        expect(lines.contains("db      | SELECT"), "interleaved output includes db line")
        expect(lines.contains("web     | world"), "partial chunks reassemble to world")
    }

    private mutating func runLogMultiplexerReplicaTests() {
        let buffer = LineBuffer()
        blockingAwait {
            let options = LogStreamOptions(tail: nil, follow: false, boot: false, mode: .plain)
            let mux = LogMultiplexer(
                prefixLabels: ["demo_web_1", "demo_web_2"],
                options: options
            ) { buffer.append($0) }
            await mux.ingest(container: "demo_web_1", prefix: "demo_web_1", chunk: "alpha\n")
            await mux.ingest(container: "demo_web_2", prefix: "demo_web_2", chunk: "beta\n")
        }

        let lines = buffer.lines.joined().split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        expect(lines.count == 2, "replica streams stay separate")
        expect(lines.contains("demo_web_1| alpha"), "first replica line intact")
        expect(lines.contains("demo_web_2| beta"), "second replica line intact")
    }

    private mutating func runLogMultiplexerWidthTests() {
        let buffer = LineBuffer()
        blockingAwait {
            let options = LogStreamOptions(tail: nil, follow: false, boot: false, mode: .plain)
            let mux = LogMultiplexer(
                prefixLabels: ["web", "verylongname"],
                options: options
            ) { buffer.append($0) }
            await mux.emit(prefix: "verylongname", line: "ok")
        }

        let line = buffer.lines.joined().trimmingCharacters(in: .newlines)
        expect(line == "verylongname| ok", "prefix width expands to longest service label")
    }

    private mutating func runLogMultiplexerPipeModeTests() {
        let buffer = LineBuffer()
        blockingAwait {
            let options = LogStreamOptions(tail: nil, follow: false, boot: false, mode: .pipe)
            let mux = LogMultiplexer(prefixLabels: ["web"], options: options) { buffer.append($0) }
            await mux.emit(prefix: "web", line: "piped")
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

    private mutating func runLogsExitPathTests() {
        let sources = makeLogSources(from: [], services: [])
        expect(sources.isEmpty, "no containers yields no log sources")

        let filteredOut = makeLogSources(
            from: [
                ProjectContainer(name: "demo_web", serviceName: "web", status: .running, publishedPorts: [])
            ],
            services: ["missing"]
        )
        expect(filteredOut.isEmpty, "unknown service filter yields no log sources")

        let buffer = LineBuffer()
        blockingAwait {
            let options = LogStreamOptions(tail: nil, follow: false, boot: false, mode: .plain)
            _ = try? await LogMultiplexer.run(sources: [], options: options) { buffer.append($0) }
        }
        expect(buffer.lines.isEmpty, "empty sources produce no streamed output")

        do {
            _ = try Logs.parse(["--tail", "0"])
            fputs("FAIL: expected throw for non-positive tail rejected\n", stderr)
            failures += 1
        } catch {
            let description = String(describing: error)
            expect(
                description.contains("--tail must be a positive integer"),
                "non-positive tail rejected at parse time"
            )
        }
    }
}
