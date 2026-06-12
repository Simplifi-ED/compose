import Foundation

#if canImport(Darwin)
import Darwin
#endif

/// Redirects process stderr during `body`, then returns the captured bytes.
enum StandardStreamCapture {
    static func captureStandardError<T>(_ body: () throws -> T) rethrows -> (result: T, captured: String) {
#if canImport(Darwin)
        let pipe = Pipe()
        let originalFD = dup(STDERR_FILENO)
        guard originalFD >= 0 else {
            return (try body(), "")
        }
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)
        let result = try body()
        fflush(stderr)
        dup2(originalFD, STDERR_FILENO)
        close(originalFD)
        try? pipe.fileHandleForWriting.close()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (result, String(bytes: data, encoding: .utf8) ?? "")
#else
        return (try body(), "")
#endif
    }
}

/// Removes ANSI SGR escape sequences for plain-text comparisons.
func stripANSI(_ string: String) -> String {
    string.replacingOccurrences(
        of: "\u{001B}\\[[0-9;]*m",
        with: "",
        options: .regularExpression
    )
}

/// Collects strings from synchronous `@Sendable` callbacks (e.g. progress sinks).
final class LineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func append(_ text: String) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(text)
    }

    var lines: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

actor TearDownRecorder {
    private(set) var names: [String] = []

    func record(_ name: String) {
        names.append(name)
    }
}

func blockingAwait<T>(_ body: @escaping @Sendable () async -> T) -> T {
    let semaphore = DispatchSemaphore(value: 0)
    let resultBox = BlockingResultBox<T>()
    Task.detached {
        resultBox.value = await body()
        semaphore.signal()
    }
    semaphore.wait()
    return resultBox.value
}

private final class BlockingResultBox<T>: @unchecked Sendable {
    var value: T!
}
