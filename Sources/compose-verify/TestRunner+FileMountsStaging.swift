import ComposeCore
import Foundation

extension TestRunner {
    mutating func runFileMountsStagingTests() throws {
        let fixturesDirectory = Self.fixtureURL("file-mounts-compose.yml").deletingLastPathComponent()
        let composeFile = try ComposeParser.parse(fileURL: Self.fixtureURL("file-mounts-compose.yml"))
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

    mutating func runRunStagingCleanupTests() throws {
        let fixturesDirectory = Self.fixtureURL("file-mounts-compose.yml").deletingLastPathComponent()
        let composeFile = try ComposeParser.parse(fileURL: Self.fixtureURL("file-mounts-compose.yml"))
        let plan = try ServicePlanner.runPlan(
            context: ServicePlanner.PlanningContext(
                composeFile: composeFile,
                projectName: "run-staging-demo",
                composeDirectory: fixturesDirectory
            ),
            serviceName: "app",
            service: composeFile.services["app"]!,
            options: RunPlanOptions(
                removeContainer: true,
                commandOverride: nil,
                interactive: false,
                processTerminal: false,
                nameSuffix: "cleanup"
            )
        )
        defer {
            ComposeFileStaging.removeProjectStaging(projectName: plan.projectName)
        }

        let stagedDirectory = ComposeFileStaging.containerDirectory(
            projectName: plan.projectName,
            containerName: plan.name
        )
        _ = try ComposeFileStaging.preparedRunArguments(for: plan)
        expect(
            FileManager.default.fileExists(atPath: stagedDirectory.path),
            "run plan stages config/secret files"
        )
        expect(plan.removeContainerAfterExit, "run --rm plan sets removeContainerAfterExit")

        RunSession.removeStagingAfterRunIfNeeded(for: plan)
        expect(
            !FileManager.default.fileExists(atPath: stagedDirectory.path),
            "run --rm success removes container staging"
        )
    }

    mutating func runDownPartialStagingTests() throws {
        let fixturesDirectory = Self.fixtureURL("file-mounts-compose.yml").deletingLastPathComponent()
        let composeFile = try ComposeParser.parse(fileURL: Self.fixtureURL("file-mounts-compose.yml"))
        let layers = try ServicePlanner.startupLayers(
            for: composeFile,
            projectName: "down-staging-interrupt",
            composeDirectory: fixturesDirectory
        )
        guard let basePlan = layers.first?.first else {
            expect(false, "down staging test produced a plan")
            return
        }
        defer { ComposeFileStaging.removeProjectStaging(projectName: basePlan.projectName) }

        let removedPlan = ServicePlan(
            serviceName: basePlan.serviceName,
            name: "\(basePlan.projectName)_app_1",
            projectName: basePlan.projectName,
            image: basePlan.image,
            runArguments: basePlan.runArguments,
            fileMounts: basePlan.fileMounts
        )
        let survivingPlan = ServicePlan(
            serviceName: basePlan.serviceName,
            name: "\(basePlan.projectName)_db_1",
            projectName: basePlan.projectName,
            image: basePlan.image,
            runArguments: basePlan.runArguments,
            fileMounts: basePlan.fileMounts
        )
        _ = try ComposeFileStaging.preparedRunArguments(for: removedPlan)
        _ = try ComposeFileStaging.preparedRunArguments(for: survivingPlan)

        let removedDirectory = ComposeFileStaging.containerDirectory(
            projectName: removedPlan.projectName,
            containerName: removedPlan.name
        )
        let survivingDirectory = ComposeFileStaging.containerDirectory(
            projectName: survivingPlan.projectName,
            containerName: survivingPlan.name
        )

        ComposeFileStaging.removeContainerStaging(
            projectName: removedPlan.projectName,
            containerName: removedPlan.name
        )
        expect(
            !FileManager.default.fileExists(atPath: removedDirectory.path),
            "down teardown removes staging for stopped container"
        )
        expect(
            FileManager.default.fileExists(atPath: survivingDirectory.path),
            "interrupted down keeps staging for surviving containers"
        )
    }
}
