import Foundation

package struct ComposeCommandInputs: Sendable {
    package let files: [String]
    package let projectName: String?
    package let profiles: [String]
    package let environment: [String: String]
    package let machineName: String?
    package let positionalServices: [String]

    package init(
        files: [String] = [],
        projectName: String? = nil,
        profiles: [String] = [],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        machineName: String? = nil,
        positionalServices: [String] = []
    ) {
        self.files = files
        self.projectName = projectName
        self.profiles = profiles
        self.environment = environment
        self.machineName = machineName
        self.positionalServices = positionalServices
    }
}

package struct ComposeCommandDownProfile: Sendable {
    package let filter: Set<String>?
    package let tearsDownAll: Bool
    package let profileFilterRequested: Bool
}

package enum ComposeCommandContext {
    package static func resolveLabelContext(
        inputs: ComposeCommandInputs,
        skipComposeFileOnExplicitProject: Bool = true,
        profileFilterRequested: Bool? = nil
    ) async throws -> ProjectOptions.LabelCommandContext {
        try ComposePathValidation.validateComposeFilePaths(inputs.files)

        let profileResolution = ProfileResolution.resolve(
            cliProfiles: inputs.profiles,
            environment: inputs.environment
        )
        let filterRequested = profileFilterRequested ?? profileResolution.profileFilterRequested
        let hasExplicitProject = inputs.projectName.map { !$0.isEmpty } ?? false

        let machineContext = try await MachineContext.resolve(machineName: inputs.machineName)

        if skipComposeFileOnExplicitProject, hasExplicitProject, !filterRequested {
            let projectName = try ProjectNameResolver.resolve(
                cliProjectName: inputs.projectName,
                composeName: nil,
                firstFileURL: nil
            )
            return ProjectOptions.LabelCommandContext(
                projectName: projectName,
                composeFile: nil,
                fileURLs: nil,
                machineContext: machineContext
            )
        }

        let discoveredFiles = try ComposeFileResolution.discover(cliFiles: inputs.files)
        let fileURLs = try ComposeFileResolution.resolvedIfPresent(files: discoveredFiles)
        let composeFile: ComposeFile?
        if let fileURLs {
            composeFile = try ComposeParser.parseForShutdown(fileURLs: fileURLs)
        } else {
            composeFile = nil
        }
        let projectName = try ProjectNameResolver.resolve(
            cliProjectName: inputs.projectName,
            composeName: composeFile?.name,
            firstFileURL: fileURLs?.first
        )
        return ProjectOptions.LabelCommandContext(
            projectName: projectName,
            composeFile: composeFile,
            fileURLs: fileURLs,
            machineContext: machineContext
        )
    }

    package static func queryServiceFilter(
        context: ProjectOptions.LabelCommandContext,
        inputs: ComposeCommandInputs
    ) throws -> Set<String>? {
        let profileResolution = ProfileResolution.resolve(
            cliProfiles: inputs.profiles,
            environment: inputs.environment
        )
        return try ProfileFilter.queryServiceFilter(
            composeFile: context.composeFile,
            activeProfiles: profileResolution.activeProfiles,
            positionalServices: inputs.positionalServices,
            profileFilterRequested: profileResolution.profileFilterRequested
        )
    }

    package static func downServiceFilter(
        context: ProjectOptions.LabelCommandContext,
        inputs: ComposeCommandInputs
    ) throws -> ComposeCommandDownProfile {
        let profileResolution = ProfileResolution.resolve(
            cliProfiles: inputs.profiles,
            environment: inputs.environment
        )
        let filter = try ProfileFilter.downServiceFilter(
            composeFile: context.composeFile,
            activeProfiles: profileResolution.activeProfiles,
            tearsDownAll: profileResolution.tearsDownAll
        )
        return ComposeCommandDownProfile(
            filter: filter,
            tearsDownAll: profileResolution.tearsDownAll,
            profileFilterRequested: profileResolution.profileFilterRequested
        )
    }
}
