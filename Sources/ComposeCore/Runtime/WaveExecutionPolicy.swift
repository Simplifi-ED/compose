import Foundation

/// Per-wave concurrency limits for container start/stop orchestration.
public struct WaveExecutionPolicy: Sendable {
    public static let unlimited = WaveExecutionPolicy(maxConcurrent: nil)

    public let maxConcurrent: Int?

    public init(maxConcurrent: Int?) {
        self.maxConcurrent = maxConcurrent
    }
}
