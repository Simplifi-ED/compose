import ArgumentParser

extension ProgressSetting: ExpressibleByArgument {}

public struct ProgressOptions: ParsableArguments {
    public init() {}

    @Option(
        help: """
        Orchestration progress on stderr while services start and stop: auto, plain, or none. \
        Does not affect runtime image-pull progress.
        """
    )
    var progress: ProgressSetting = .auto

    /// Resolves the CLI setting against the live stderr terminal.
    func resolvedDisplay() -> ProgressDisplay {
        ProgressDisplay.resolve(setting: progress)
    }
}
