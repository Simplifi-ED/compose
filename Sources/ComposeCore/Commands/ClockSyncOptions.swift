import ArgumentParser

public struct ClockSyncOptions: ParsableArguments {
    public init() {}

    @Flag(
        name: .long,
        help: "Disable guest clock sync after Mac wake (or set COMPOSE_CLOCK_SYNC=0)."
    )
    var noClockSync = false

    package var isDisabled: Bool { noClockSync }
}
