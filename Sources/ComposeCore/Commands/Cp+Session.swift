import Foundation

extension Cp {
    func printCpDryRun(
        manifest: DryRunManifest,
        targets: [ProjectContainer],
        direction: CpSession.Direction,
        source: String,
        destination: String
    ) async {
        for target in targets {
            await manifest.recordCp(
                container: target.name,
                direction: direction,
                source: source,
                destination: destination
            )
        }
        await manifest.printLines()
    }
}
