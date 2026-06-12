import ArgumentParser
import ComposeCore

@main
struct ComposeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "compose",
        abstract: "Define and run multi-container applications with Apple container.",
        subcommands: [
            Up.self, Down.self, Ps.self, Logs.self, Exec.self, Cp.self, Run.self, Top.self, Config.self, Watch.self,
            Save.self, Load.self
        ]
    )
}
