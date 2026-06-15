import Foundation

extension DryRunManifest {
    public func recordDiskTrims(
        containerNames: [String],
        volumeNames: [String],
        machineName: String?
    ) {
        beginGroupedSection()
        for name in containerNames.sorted() {
            appendTrimLine(
                sortKey: "trim:container:\(name)",
                line: DryRunManifestFormatting.formatDiskTrimContainer(name: name)
            )
        }
        for name in volumeNames.sorted() {
            appendTrimLine(
                sortKey: "trim:volume:\(name)",
                line: DryRunManifestFormatting.formatDiskTrimVolume(name: name)
            )
        }
        if let machineName {
            appendTrimLine(
                sortKey: "trim:machine:\(machineName)",
                line: DryRunManifestFormatting.formatDiskTrimMachine(name: machineName)
            )
        }
    }
}
