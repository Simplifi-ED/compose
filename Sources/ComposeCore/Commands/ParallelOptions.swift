import ArgumentParser

public struct ParallelOptions: ParsableArguments {
    public init() {}

    @Option(
        name: .customLong("parallel"),
        help: """
        Maximum containers started, stopped, paused, or unpaused at once within each \
        dependency wave (or a single batch for pause/unpause). Default: no limit.
        """
    )
    var parallel: Int?

    public func validate() throws {
        try Self.validateParallel(parallel)
    }

    package func resolvedMaxConcurrent() -> Int? {
        parallel
    }

    package static func validateParallel(_ value: Int?) throws {
        if let value, value <= 0 {
            throw ValidationError("--parallel must be a positive integer.")
        }
    }
}
