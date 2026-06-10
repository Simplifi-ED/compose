import Foundation

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
