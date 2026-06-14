import ArgumentParser
import ComposeCore

@main
struct ComposeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "compose",
        abstract: "Define and run multi-container applications with Apple container.",
        subcommands: ComposeSubcommandRegistry.all
    )
}
