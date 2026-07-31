import Foundation

package enum ProjectScalePlanning {
    package struct Plan: Sendable {
        package let fileURLs: [URL]
        package let composeFile: ComposeFile
        package let projectName: String
        package let composeDirectory: URL
        package let activeProfiles: Set<String>
        package let scaleOverrides: [String: Int]
        package let buildPlans: [BuildRunner.Plan]
        package let networkPlans: [NetworkPlanning.Plan]
        package let volumePlans: [VolumePlanning.Plan]
    }

    package static func resolve(
        inputs: ComposeCommandInputs,
        scaleOverrides: [String: Int],
        machineName: String? = nil,
        requireExplicitFiles: Bool = false
    ) throws -> Plan {
        let seed = try loadSeed(
            inputs: inputs,
            scaleOverrides: scaleOverrides,
            machineName: machineName,
            requireExplicitFiles: requireExplicitFiles
        )
        return try assemblePlan(seed)
    }

    private struct Seed: Sendable {
        let fileURLs: [URL]
        let composeFile: ComposeFile
        let projectName: String
        let composeDirectory: URL
        let activeProfiles: Set<String>
        let scaleOverrides: [String: Int]
    }

    private static func loadSeed(
        inputs: ComposeCommandInputs,
        scaleOverrides: [String: Int],
        machineName: String?,
        requireExplicitFiles: Bool
    ) throws -> Seed {
        try ComposePathValidation.validateComposeFilePaths(inputs.files)
        if requireExplicitFiles, inputs.files.isEmpty {
            throw ComposeError.invalidComposeFilePath(
                "scale requires at least one compose file path in files[]"
            )
        }
        guard !scaleOverrides.isEmpty else {
            throw ComposeError.scaleRequiresTargets
        }
        let fileURLs = try ComposeFileResolution.resolved(
            files: try ComposeFileResolution.discover(cliFiles: inputs.files)
        )
        let composeFile = try ComposeParser.parse(fileURLs: fileURLs)
        try DependencyValidation.validateMachineMode(
            services: composeFile.services,
            machineName: machineName
        )
        let projectName = try ProjectNameResolver.resolve(
            cliProjectName: inputs.projectName,
            composeName: composeFile.name,
            firstFileURL: fileURLs[0]
        )
        let profileResolution = ProfileResolution.resolve(
            cliProfiles: inputs.profiles,
            environment: inputs.environment
        )
        return Seed(
            fileURLs: fileURLs,
            composeFile: composeFile,
            projectName: projectName,
            composeDirectory: fileURLs[0].deletingLastPathComponent(),
            activeProfiles: profileResolution.activeProfiles,
            scaleOverrides: scaleOverrides
        )
    }

    private static func assemblePlan(_ seed: Seed) throws -> Plan {
        let scaledServiceNames = Set(seed.scaleOverrides.keys)
        return Plan(
            fileURLs: seed.fileURLs,
            composeFile: seed.composeFile,
            projectName: seed.projectName,
            composeDirectory: seed.composeDirectory,
            activeProfiles: seed.activeProfiles,
            scaleOverrides: seed.scaleOverrides,
            buildPlans: try BuildRunner.plans(
                composeFile: seed.composeFile,
                projectName: seed.projectName,
                composeDirectory: seed.composeDirectory,
                activeProfiles: seed.activeProfiles
            ).filter { scaledServiceNames.contains($0.serviceName) },
            networkPlans: try NetworkPlanning.plans(
                composeFile: seed.composeFile,
                projectName: seed.projectName,
                activeServiceNames: scaledServiceNames
            ),
            volumePlans: try VolumePlanning.plans(
                composeFile: seed.composeFile,
                projectName: seed.projectName,
                activeServiceNames: scaledServiceNames
            )
        )
    }
}
