import Foundation

extension ServicePlanner {
    package static func runPlan(
        context: PlanningContext,
        serviceName: String,
        service: ComposeService,
        options: RunPlanOptions
    ) throws -> ServicePlan {
        let image = try BuildImageResolver.resolvedImageTag(
            projectName: context.projectName,
            serviceName: serviceName,
            service: service
        )

        let baseName = runContainerBaseName(
            serviceName: serviceName,
            service: service,
            projectName: context.projectName
        )
        let name = "\(baseName)_run_\(options.nameSuffix)"

        try ComposeFileMountResolver.validate(
            composeFile: context.composeFile,
            activeServiceNames: [serviceName]
        )
        try NetworkPlanning.validate(
            composeFile: context.composeFile,
            activeServiceNames: [serviceName]
        )
        try PlatformPlanning.validate(
            services: context.composeFile.services,
            activeServiceNames: [serviceName],
            machineName: context.machineName
        )

        var arguments: [String] = ["--name", name]
        if options.removeContainer {
            arguments.append("--rm")
        }
        if options.interactive {
            arguments.append("-i")
        }
        if options.processTerminal {
            arguments.append("-t")
        }
        let command = if let override = options.commandOverride, !override.isEmpty {
            override
        } else {
            ServiceRunMapping.commandArguments(service.command)
        }

        return try assemblePlan(
            PlanAssembly(
                context: context,
                serviceName: serviceName,
                service: service,
                name: name,
                image: image,
                runArguments: arguments,
                command: command,
                removeContainerAfterExit: options.removeContainer
            )
        )
    }

    package static func buildUpPlan(
        context: PlanningContext,
        serviceName: String,
        service: ComposeService,
        replicaIndex: Int
    ) throws -> ServicePlan {
        let image = try BuildImageResolver.resolvedImageTag(
            projectName: context.projectName,
            serviceName: serviceName,
            service: service
        )

        let name = ReplicaPlanning.indexedContainerName(
            projectName: context.projectName,
            serviceName: serviceName,
            index: replicaIndex
        )

        return try assemblePlan(
            PlanAssembly(
                context: context,
                serviceName: serviceName,
                service: service,
                name: name,
                image: image,
                runArguments: ["-d", "--name", name],
                command: ServiceRunMapping.commandArguments(service.command),
                containerNumber: replicaIndex,
                replicaIndex: replicaIndex
            )
        )
    }

    private struct PlanAssembly {
        let context: PlanningContext
        let serviceName: String
        let service: ComposeService
        let name: String
        let image: String
        let runArguments: [String]
        let command: [String]
        var containerNumber: Int = 1
        var replicaIndex: Int = 1
        var removeContainerAfterExit: Bool = false
    }

    private static func assemblePlan(_ assembly: PlanAssembly) throws -> ServicePlan {
        var arguments = assembly.runArguments
        try ServiceRunMapping.appendServiceRunConfiguration(
            to: &arguments,
            configuration: ServiceRunConfiguration(
                serviceName: assembly.serviceName,
                service: assembly.service,
                projectName: assembly.context.projectName,
                composeDirectory: assembly.service.projectDirectory(
                    orDefault: assembly.context.composeDirectory
                ),
                image: assembly.image,
                command: assembly.command,
                containerNumber: assembly.containerNumber,
                machineName: assembly.context.machineName
            )
        )

        let fileMounts = try ComposeFileMountResolver.plannedMounts(
            for: assembly.service,
            composeFile: assembly.context.composeFile
        )

        return ServicePlan(
            serviceName: assembly.serviceName,
            name: assembly.name,
            projectName: assembly.context.projectName,
            image: assembly.image,
            runArguments: arguments,
            fileMounts: fileMounts,
            replicaIndex: assembly.replicaIndex,
            removeContainerAfterExit: assembly.removeContainerAfterExit
        )
    }
}
