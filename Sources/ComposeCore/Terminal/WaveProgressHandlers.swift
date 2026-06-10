import Foundation

/// Optional orchestration progress callbacks for `up`/`down` waves.
/// Purely observational: wave ordering and rollback behavior are unaffected.
public struct WaveProgressHandlers: Sendable {
    public var onWaveStart: (@Sendable (_ wave: Int, _ totalWaves: Int, _ services: [String]) async -> Void)?
    public var onServiceComplete: (@Sendable (_ service: String, _ succeeded: Bool) async -> Void)?
    public var onWaveComplete: (@Sendable (_ wave: Int) async -> Void)?

    public init(
        onWaveStart: (@Sendable (Int, Int, [String]) async -> Void)? = nil,
        onServiceComplete: (@Sendable (String, Bool) async -> Void)? = nil,
        onWaveComplete: (@Sendable (Int) async -> Void)? = nil
    ) {
        self.onWaveStart = onWaveStart
        self.onServiceComplete = onServiceComplete
        self.onWaveComplete = onWaveComplete
    }
}
