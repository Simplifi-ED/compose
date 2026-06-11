import ArgumentParser

public struct DryRunOptions: ParsableArguments {
    public init() {}

    @Flag(
        name: .long,
        help: "Print planned container operations without changing system state."
    )
    var dryRun = false

    var isEnabled: Bool { dryRun }
}
