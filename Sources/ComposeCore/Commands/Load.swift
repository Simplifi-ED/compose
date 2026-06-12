import ArgumentParser
import Foundation

public struct Load: AsyncParsableCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        abstract: "Import images and manifest from a compose stack archive."
    )

    @OptionGroup
    var machineOptions: MachineOptions

    @Option(
        name: .shortAndLong,
        help: "Path to the stack archive (.tar)."
    )
    var input: String

    @Option(
        name: .shortAndLong,
        help: "Write bundled compose.yaml to this path (default: compose.yaml)."
    )
    var composeFile: String?

    @Flag(
        name: .long,
        help: "Load images even if the nested OCI archive contains invalid members."
    )
    var force = false

    public func run() async throws {
        try machineOptions.rejectIfUnsupported(commandName: "load")
        let inputURL = URL(fileURLWithPath: input).standardizedFileURL
        let result = try await ArchiveExport.load(inputURL: inputURL, force: force)

        let composeOutputURL = URL(
            fileURLWithPath: composeFile ?? ComposeArchiveFormat.composeYAMLPath
        ).standardizedFileURL
        try result.composeYAML.write(to: composeOutputURL, atomically: true, encoding: .utf8)

        for reference in result.loadedReferences {
            print(reference)
        }
        print("Project: \(result.manifest.projectName) (\(result.manifest.serviceCount) services in manifest)")
        fputs("Wrote resolved compose file to \(composeOutputURL.path)\n", stderr)
        print("Run compose up -f \(composeOutputURL.path) to start the stack.")
    }
}
