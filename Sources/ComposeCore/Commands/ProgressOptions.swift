import ArgumentParser

extension ProgressSetting: ExpressibleByArgument {}

public struct ProgressOptions: ParsableArguments {
    public init() {}

    @Option(help: "Progress output while services start and stop: auto, plain, or none.")
    var progress: ProgressSetting = .auto

    /// Resolves the CLI setting against the live stderr terminal.
    func resolvedDisplay() -> ProgressDisplay {
        ProgressDisplay.resolve(setting: progress)
    }
}
