import ContainerCommands
import Foundation

package enum BuildRunner {
    package struct Plan: Sendable, Equatable {
        package let serviceName: String
        package let tag: String
        package let contextURL: URL
        package let contextDisplayPath: String
        package let dockerfile: String?
        package let args: [String: String]
        package let target: String?
    }

    package static func plans(
        composeFile: ComposeFile,
        projectName: String,
        composeDirectory: URL,
        activeProfiles: Set<String>
    ) throws -> [Plan] {
        let activeServices = try ProfileFilter.activeServices(
            from: composeFile.services,
            activeProfiles: activeProfiles
        )
        let activeServiceNames = Set(activeServices.keys)
        try BuildValidator.validate(
            composeFile: composeFile,
            projectName: projectName,
            composeDirectory: composeDirectory,
            activeServiceNames: activeServiceNames
        )

        return try BuildImageResolver.servicesNeedingBuild(from: activeServices).map { entry in
            try makePlan(
                serviceName: entry.name,
                service: entry.service,
                projectName: projectName,
                composeDirectory: composeDirectory
            )
        }
    }

    package static func makePlan(
        serviceName: String,
        service: ComposeService,
        projectName: String,
        composeDirectory: URL
    ) throws -> Plan {
        PlatformPlanning.warnBuildPlatformMismatch(
            serviceName: serviceName,
            platform: service.platform
        )
        let build = service.build!
        let serviceDirectory = service.projectDirectory(orDefault: composeDirectory)
        let contextURL = try BuildValidator.resolvedContextURL(
            build: build,
            serviceName: serviceName,
            composeDirectory: serviceDirectory
        )
        let tag = try BuildImageResolver.resolvedImageTag(
            projectName: projectName,
            serviceName: serviceName,
            service: service
        )
        return Plan(
            serviceName: serviceName,
            tag: tag,
            contextURL: contextURL,
            contextDisplayPath: build.context,
            dockerfile: build.dockerfile,
            args: build.args,
            target: build.target
        )
    }

    package static func buildAll(
        _ plans: [Plan],
        progress: ProgressSetting?,
        dryRunManifest: DryRunManifest?,
        machineContext: MachineContext = .applicationSandbox
    ) async throws {
        for plan in plans {
            if let dryRunManifest {
                await dryRunManifest.recordBuild(
                    service: plan.serviceName,
                    tag: plan.tag,
                    context: plan.contextDisplayPath,
                    dockerfile: plan.dockerfile
                )
                continue
            }
            do {
                try await executeBuild(
                    plan: plan,
                    progress: progress,
                    machineContext: machineContext
                )
            } catch {
                OsLogTelemetry.enabled {
                    OsLogTelemetry.build.error(
                        """
                        event=build_failed service=\(plan.serviceName, privacy: .public) \
                        error_type=\(String(describing: type(of: error)), privacy: .public)
                        """
                    )
                }
                throw ComposeError.buildFailed(service: plan.serviceName, underlying: error)
            }
        }
    }

    private static func executeBuild(
        plan: Plan,
        progress: ProgressSetting?,
        machineContext: MachineContext
    ) async throws {
        let machine = machineContext.machineName ?? "host"
        OsLogTelemetry.enabled {
            if let dockerfile = plan.dockerfile {
                OsLogTelemetry.build.info(
                    """
                    event=build_start service=\(plan.serviceName, privacy: .public) \
                    dockerfile=\(dockerfile, privacy: .private) \
                    machine=\(machine, privacy: .public)
                    """
                )
            } else {
                OsLogTelemetry.build.info(
                    """
                    event=build_start service=\(plan.serviceName, privacy: .public) \
                    machine=\(machine, privacy: .public)
                    """
                )
            }
        }
        if machineContext.isMachineMode {
            let booted = try machineContext.bootedContext()
            let arguments = try buildArguments(for: plan, progress: progress)
            try await MachineInVMRunner.run(
                snapshot: booted.snapshot,
                containerArguments: ["build"] + arguments
            )
        } else {
            let arguments = try buildArguments(for: plan, progress: progress)
            let command = try Application.BuildCommand.parse(arguments)
            try await command.run()
        }
        OsLogTelemetry.enabled {
            OsLogTelemetry.build.info(
                """
                event=build_success service=\(plan.serviceName, privacy: .public) \
                machine=\(machine, privacy: .public)
                """
            )
        }
    }
}
