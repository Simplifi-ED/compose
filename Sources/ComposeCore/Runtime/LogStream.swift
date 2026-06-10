import ContainerAPIClient
import ContainerizationError
import Darwin
import Foundation

// Tail/follow behavior mirrors upstream Application.ContainerLogs:
// https://github.com/apple/container/blob/main/Sources/ContainerCommands/Container/ContainerLogs.swift

/// Formats a single log line with a per-service prefix.
package enum LogFormat {
    package static func formatLine(
        service: String,
        line: String,
        mode: TerminalMode,
        width: Int
    ) -> String {
        "\(ANSIPrefix.format(serviceName: service, mode: mode, width: width))\(line)\n"
    }
}

/// Reassembles byte chunks into complete newline-delimited lines.
package struct LogLineAssembler: Sendable {
    private var pending = ""

    package init() {}

    package mutating func append(_ chunk: String) -> [String] {
        guard !chunk.isEmpty else { return [] }
        pending += chunk
        var lines: [String] = []
        while let newlineIndex = pending.firstIndex(of: "\n") {
            let line = String(pending[..<newlineIndex])
            lines.append(line)
            pending.removeSubrange(...newlineIndex)
        }
        return lines
    }

    package mutating func finish() -> [String] {
        guard !pending.isEmpty else { return [] }
        let line = pending
        pending = ""
        return [line]
    }
}

package struct ServiceLogSource: Sendable {
    package let containerName: String
    package let serviceLabel: String

    package init(containerName: String, serviceLabel: String) {
        self.containerName = containerName
        self.serviceLabel = serviceLabel
    }
}

package struct LogStreamOptions: Sendable {
    package let tail: Int?
    package let follow: Bool
    package let boot: Bool
    package let mode: TerminalMode

    package init(tail: Int?, follow: Bool, boot: Bool, mode: TerminalMode) {
        self.tail = tail
        self.follow = follow
        self.boot = boot
        self.mode = mode
    }
}

/// Reads historical log content from a file handle.
package enum LogTailReader {
    /// Splits log text into lines, preserving intentional blank lines.
    /// Strips only the trailing empty segment produced by a final newline.
    package static func splitLogLines(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var lines = text.components(separatedBy: .newlines)
        if lines.last == "" {
            lines.removeLast()
        }
        return lines
    }

    package static func readLines(from handle: FileHandle, tail: Int?) throws -> [String] {
        if let tail {
            return try readLastLines(from: handle, count: tail)
        }
        guard let data = try handle.readToEnd() else { return [] }
        guard let text = String(data: data, encoding: .utf8) else {
            throw ContainerizationError(
                .internalError,
                message: "failed to convert container logs to utf8"
            )
        }
        return splitLogLines(text)
    }

    private static func readLastLines(from handle: FileHandle, count: Int) throws -> [String] {
        var buffer = Data()
        let size = try handle.seekToEnd()
        var offset = size
        var lines: [String] = []

        while offset > 0 {
            if lines.count >= count, String(data: buffer, encoding: .utf8) != nil {
                break
            }

            let readSize = min(1024, offset)
            offset -= readSize
            try handle.seek(toOffset: offset)

            let data = handle.readData(ofLength: Int(readSize))
            buffer.insert(contentsOf: data, at: 0)

            guard let text = String(data: buffer, encoding: .utf8) else {
                continue
            }
            lines = splitLogLines(text)
        }

        guard let text = String(data: buffer, encoding: .utf8) else {
            throw ContainerizationError(
                .internalError,
                message: "failed to convert container logs to utf8"
            )
        }
        return Array(splitLogLines(text).suffix(count))
    }
}

/// Streams new log chunks from a file handle after the current offset.
package enum LogFollowReader {
    package static func chunks(from handle: FileHandle) -> AsyncStream<String> {
        AsyncStream { continuation in
            handle.readabilityHandler = { activeHandle in
                let data = activeHandle.availableData
                if data.isEmpty {
                    do {
                        _ = try activeHandle.seekToEnd()
                    } catch {
                        activeHandle.readabilityHandler = nil
                        continuation.finish()
                        return
                    }
                    return
                }
                guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return }
                continuation.yield(text)
            }
            continuation.onTermination = { @Sendable _ in
                handle.readabilityHandler = nil
            }
        }
    }
}

/// Multiplexes per-service log lines onto a single write sink with stable prefixes.
package actor LogMultiplexer {
    private let options: LogStreamOptions
    private let write: @Sendable (String) -> Void
    private var prefixWidth: Int
    private var assemblers: [String: LogLineAssembler] = [:]

    package init(
        serviceLabels: [String],
        options: LogStreamOptions,
        write: @escaping @Sendable (String) -> Void
    ) {
        self.options = options
        self.write = write
        self.prefixWidth = max(ANSIPrefix.defaultWidth, serviceLabels.map(\.count).max() ?? 0)
    }

    package func emit(service: String, line: String) {
        write(LogFormat.formatLine(
            service: service,
            line: line,
            mode: options.mode,
            width: prefixWidth
        ))
    }

    /// Ingest raw log chunks and emit complete prefixed lines.
    package func ingest(service: String, chunk: String) {
        var assembler = assemblers[service] ?? LogLineAssembler()
        for line in assembler.append(chunk) {
            emit(service: service, line: line)
        }
        assemblers[service] = assembler
    }

    package func finishPending(service: String) {
        guard var assembler = assemblers[service] else { return }
        for line in assembler.finish() {
            emit(service: service, line: line)
        }
        assemblers[service] = assembler
    }

    package static func run(
        sources: [ServiceLogSource],
        options: LogStreamOptions,
        write: @escaping @Sendable (String) -> Void = defaultWrite
    ) async throws {
        guard !sources.isEmpty else { return }

        let labels = sources.map(\.serviceLabel)
        let multiplexer = LogMultiplexer(serviceLabels: labels, options: options, write: write)

        try await withThrowingTaskGroup(of: Void.self) { group in
            defer { group.cancelAll() }
            for source in sources {
                group.addTask {
                    let handle = try await logHandle(for: source, options: options)
                    try await emitSnapshot(
                        handle: handle,
                        source: source,
                        multiplexer: multiplexer,
                        options: options
                    )
                    if options.follow {
                        try await followContainer(
                            handle: handle,
                            source: source,
                            multiplexer: multiplexer
                        )
                    }
                }
            }
            do {
                try await group.waitForAll()
            } catch is CancellationError {
                return
            }
        }
    }

    private static func defaultWrite(_ text: String) {
        print(text, terminator: "")
    }

    private static func logHandle(
        for source: ServiceLogSource,
        options: LogStreamOptions
    ) async throws -> FileHandle {
        let client = ContainerClient()
        let handles = try await client.logs(id: source.containerName)
        let index = options.boot ? 1 : 0
        guard handles.indices.contains(index) else {
            throw ContainerizationError(
                .internalError,
                message: options.boot
                    ? "no boot log available for container \(source.containerName)"
                    : "no log file handles returned for container \(source.containerName)"
            )
        }
        return handles[index]
    }

    private static func emitSnapshot(
        handle: FileHandle,
        source: ServiceLogSource,
        multiplexer: LogMultiplexer,
        options: LogStreamOptions
    ) async throws {
        let snapshotLines = try LogTailReader.readLines(from: handle, tail: options.tail)
        for line in snapshotLines {
            await multiplexer.emit(service: source.serviceLabel, line: line)
        }
    }

    private static func followContainer(
        handle: FileHandle,
        source: ServiceLogSource,
        multiplexer: LogMultiplexer
    ) async throws {
        _ = try handle.seekToEnd()

        for await chunk in LogFollowReader.chunks(from: handle) {
            if Task.isCancelled {
                break
            }
            await multiplexer.ingest(service: source.serviceLabel, chunk: chunk)
        }
        await multiplexer.finishPending(service: source.serviceLabel)
    }
}

/// Builds log stream sources from startup plans started by `compose up`.
package func makeLogSources(from plans: [ServicePlan]) -> [ServiceLogSource] {
    plans.map { plan in
        ServiceLogSource(containerName: plan.name, serviceLabel: plan.serviceName)
    }
}

/// Builds log stream sources for the selected project containers.
package func makeLogSources(
    from containers: [ProjectContainer],
    services: [String]
) -> [ServiceLogSource] {
    let filter = services.isEmpty ? nil : Set(services)
    let filtered = ProjectStatus.filteredContainers(from: containers, filter: filter)
    return filtered.map { container in
        ServiceLogSource(
            containerName: container.name,
            serviceLabel: progressServiceLabel(
                containerName: container.name,
                serviceName: container.serviceName
            )
        )
    }
}
