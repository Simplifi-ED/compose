import Foundation

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
    Task {
        resultBox.value = await body()
        semaphore.signal()
    }
    semaphore.wait()
    return resultBox.value
}

private final class BlockingResultBox<T>: @unchecked Sendable {
    var value: T!
}
