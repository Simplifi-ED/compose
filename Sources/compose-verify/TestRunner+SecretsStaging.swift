import ComposeCore
import Foundation

extension TestRunner {
    mutating func runSecretsStagingTests() throws {
        let fixturesDirectory = Self.fixtureURL("secrets-compose.yml").deletingLastPathComponent()
        let composeFile = try ComposeParser.parse(fileURL: Self.fixtureURL("secrets-compose.yml"))
        let layers = try ServicePlanner.startupLayers(
            for: composeFile,
            projectName: "staging-demo",
            composeDirectory: fixturesDirectory
        )
        guard let plan = layers.first?.first else {
            expect(false, "staging test produced a plan")
            return
        }

        let stagedDirectory = ComposeFileStaging.containerDirectory(
            projectName: plan.projectName,
            containerName: plan.name
        )
        defer {
            ComposeFileStaging.removeProjectStaging(projectName: plan.projectName)
        }

        _ = try ComposeFileStaging.preparedRunArguments(for: plan)
        expect(
            FileManager.default.fileExists(atPath: stagedDirectory.path),
            "staging creates container directory"
        )

        ComposeFileStaging.removeContainerStaging(
            projectName: plan.projectName,
            containerName: plan.name
        )
        expect(
            !FileManager.default.fileExists(atPath: stagedDirectory.path),
            "removeContainerStaging deletes staged files"
        )

        _ = try ComposeFileStaging.preparedRunArguments(for: plan)
        ServiceRunner.cleanupOrphanStaging(layers: layers, startedWaves: [])
        expect(
            !FileManager.default.fileExists(atPath: stagedDirectory.path),
            "cleanupOrphanStaging removes unstaged-success paths"
        )

        ComposeFileStaging.removeProjectStaging(projectName: plan.projectName)
        let projectDirectory = ComposeFileStaging.projectRoot(projectName: plan.projectName)
        expect(
            !FileManager.default.fileExists(atPath: projectDirectory.path),
            "removeProjectStaging deletes project staging tree"
        )
    }
}
