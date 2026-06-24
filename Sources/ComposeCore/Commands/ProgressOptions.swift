import ArgumentParser
import Foundation

extension ProgressSetting: ExpressibleByArgument {}

package struct ComposeProgressResolution: Sendable, Equatable {
    package let display: ProgressDisplay
    package let pipeOutput: Bool

    package var imagePullOutput: ImagePullOutput {
        ImagePullOutput(display: display, pipeOutput: pipeOutput)
    }
}

public struct ProgressOptions: ParsableArguments {
    public init() {}

    @Option(
        help: """
        Compose progress on stderr for image pulls and service start/stop waves: auto, plain, or none.
        """
    )
    var progress: ProgressSetting = .auto

    /// Resolves the CLI setting against the live stderr terminal.
    func resolvedDisplay() -> ProgressDisplay {
        resolvedProgress().display
    }

    /// Resolves image-pull progress against stderr and preserves pipe-vs-TTY behavior.
    func resolvedImagePullOutput() -> ImagePullOutput {
        resolvedProgress().imagePullOutput
    }

    func resolvedProgress() -> ComposeProgressResolution {
        let mode = TerminalMode.resolve(fileDescriptor: FileHandle.standardError.fileDescriptor)
        return ComposeProgressResolution(
            display: ProgressDisplay.resolve(setting: progress, terminalMode: mode),
            pipeOutput: mode == .pipe
        )
    }
}
