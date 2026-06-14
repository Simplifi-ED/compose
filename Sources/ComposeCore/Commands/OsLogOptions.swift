import ArgumentParser

public struct OsLogOptions: ParsableArguments {
    public init() {}

    @Flag(
        name: .long,
        help: "Disable Unified Logging telemetry and Instruments signposts (or set COMPOSE_OSLOG=0)."
    )
    var noOslog = false

    package var isDisabled: Bool { noOslog }
}
