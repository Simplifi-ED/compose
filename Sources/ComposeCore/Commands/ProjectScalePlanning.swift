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
        requireExplicitFiles: Bool = false,
        dryRun: Bool = false
    ) throws -> Plan {
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
        let composeDirectory = fileURLs[0].deletingLastPathComponent()
        let scaledServiceNames = Set(scaleOverrides.keys)
        return Plan(
            fileURLs: fileURLs,
            composeFile: composeFile,
            projectName: projectName,
            composeDirectory: composeDirectory,
            activeProfiles: profileResolution.activeProfiles,
            scaleOverrides: scaleOverrides,
            buildPlans: try BuildRunner.plans(
                composeFile: composeFile,
                projectName: projectName,
                composeDirectory: composeDirectory,
                activeProfiles: profileResolution.activeProfiles
            ).filter { scaledServiceNames.contains($0.serviceName) },
            networkPlans: try NetworkPlanning.plans(
                composeFile: composeFile,
                projectName: projectName,
                activeServiceNames: scaledServiceNames
            ),
            volumePlans: try VolumePlanning.plans(
                composeFile: composeFile,
                projectName: projectName,
                activeServiceNames: scaledServiceNames
            )
        )
    }
}
