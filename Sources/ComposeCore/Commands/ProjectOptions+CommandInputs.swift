import Foundation

extension ProjectOptions {
    package func composeCommandInputs(
        profiles: [String] = [],
        machineName: String? = nil,
        services: [String] = [],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> ComposeCommandInputs {
        ComposeCommandInputs(
            files: files,
            projectName: projectName,
            profiles: profiles,
            environment: environment,
            machineName: machineName,
            positionalServices: services
        )
    }

    package func resolvedLabelCommandContext(
        skipComposeFileOnExplicitProject: Bool = false,
        profileFilterRequested: Bool = false,
        profiles: [String] = [],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        machineContext: MachineContext = .applicationSandbox
    ) throws -> LabelCommandContext {
        try ComposeCommandContext.resolveLabelContext(
            inputs: composeCommandInputs(
                profiles: profiles,
                machineName: machineContext.machineName,
                environment: environment
            ),
            machineContext: machineContext,
            skipComposeFileOnExplicitProject: skipComposeFileOnExplicitProject,
            profileFilterRequested: profileFilterRequested
        )
    }
}
