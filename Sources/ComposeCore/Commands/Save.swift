import ArgumentParser
import Foundation

public struct Save: AsyncParsableCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        abstract: "Export project images and resolved compose configuration to a portable archive."
    )

    @OptionGroup
    var projectOptions: ProjectOptions

    @OptionGroup
    var profileOptions: ProfileOptions

    @OptionGroup
    var scaleOptions: ScaleOptions

    @OptionGroup
    var machineOptions: MachineOptions

    @OptionGroup
    var dryRunOptions: DryRunOptions

    @Option(
        name: .shortAndLong,
        help: "Path for the stack archive (.tar)."
    )
    var output: String

    public func run() async throws {
        try machineOptions.rejectIfUnsupported(commandName: "save")
        let fileURLs = try projectOptions.resolvedFileURLs()
        let composeFile = try ComposeParser.parse(fileURLs: fileURLs)
        let projectName = try projectOptions.resolvedProjectName(
            composeFile: composeFile,
            fileURL: fileURLs[0]
        )
        let scaleOverrides = try scaleOptions.resolvedScaleOverrides()
        let plan = try ArchiveExport.plan(
            fileURLs: fileURLs,
            projectName: projectName,
            activeProfiles: profileOptions.activeProfileSet,
            scaleOverrides: scaleOverrides
        )

        let outputURL = URL(fileURLWithPath: output).standardizedFileURL

        if dryRunOptions.isEnabled {
            for entry in plan.imageEntries {
                print(DryRunManifestFormatting.formatSaveImage(
                    service: entry.service,
                    reference: entry.reference
                ))
            }
            print(DryRunManifestFormatting.formatSaveArchive(
                path: outputURL.path,
                imageCount: plan.uniqueReferences.count,
                serviceCount: plan.imageEntries.count
            ))
            return
        }

        try await ArchiveExport.save(plan: plan, outputURL: outputURL)
        let summary = "Saved \(plan.uniqueReferences.count) image(s) "
            + "for \(plan.imageEntries.count) service(s) to \(outputURL.path)\n"
        fputs(summary, stderr)
    }
}
