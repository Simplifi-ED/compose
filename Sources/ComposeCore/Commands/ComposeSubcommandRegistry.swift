import ArgumentParser
import Foundation

/// Single registry for compose subcommands — used by the plugin entry point and doctor discovery.
package enum ComposeSubcommandRegistry {
    package static let all: [any AsyncParsableCommand.Type] = [
        Up.self,
        Down.self,
        Pause.self,
        Unpause.self,
        Ps.self,
        Logs.self,
        Events.self,
        Exec.self,
        Cp.self,
        Run.self,
        Top.self,
        Config.self,
        Watch.self,
        Save.self,
        Load.self,
        Doctor.self,
        Xpc.self
    ]

    package static var commandNames: [String] {
        all.map { String(describing: $0).lowercased() }
    }

    package static func parseSubcommands(from helpText: String) -> Set<String> {
        var names: Set<String> = []
        var inSubcommands = false
        for line in helpText.split(whereSeparator: \.isNewline) {
            let lineString = String(line)
            let trimmed = lineString.trimmingCharacters(in: .whitespaces)
            if trimmed == "SUBCOMMANDS:" {
                inSubcommands = true
                continue
            }
            guard inSubcommands else { continue }
            if trimmed.hasPrefix("See ") || trimmed.hasPrefix("OPTIONS:") {
                break
            }
            guard !trimmed.isEmpty, lineString.first?.isWhitespace == true else { continue }
            let namesSegment = trimmed.split(separator: "  ", maxSplits: 1).first.map(String.init) ?? trimmed
            for part in namesSegment.split(separator: ",", omittingEmptySubsequences: true) {
                let name = part.trimmingCharacters(in: .whitespaces).lowercased()
                guard !name.isEmpty, name.allSatisfy({ $0.isLetter || $0 == "-" }) else { continue }
                names.insert(name)
            }
        }
        return names
    }
}
