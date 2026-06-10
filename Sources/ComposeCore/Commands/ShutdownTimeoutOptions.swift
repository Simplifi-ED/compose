import ArgumentParser
import Foundation

/// Reserved for future `attach up`, `exec`, and `top` commands that stop project containers (#21–#20).
public struct ShutdownTimeoutOptions: ParsableArguments {
    public init() {}

    @Option(
        name: .shortAndLong,
        help: "Seconds to wait after SIGTERM before SIGKILL when stopping containers."
    )
    var timeout: Int32 = GracefulStopOptions.defaultGraceSeconds

    public func validate() throws {
        try Self.validateTimeout(timeout)
    }

    package func gracefulStopOptions() -> GracefulStopOptions {
        GracefulStopOptions(graceSeconds: timeout)
    }

    package static func validateTimeout(_ value: Int32) throws {
        if value <= 0 {
            throw ValidationError("--timeout must be a positive integer.")
        }
    }
}
