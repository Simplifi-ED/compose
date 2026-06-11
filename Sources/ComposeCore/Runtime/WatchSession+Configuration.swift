import Foundation

extension WatchSession {
    package struct BuildContext: Sendable {
        package let composeFile: ComposeFile
        package let projectName: String
        package let composeDirectory: URL
        package let activeProfiles: Set<String>
        package let scaleOverrides: [String: Int]
        package let serviceFilter: Set<String>?
        package let containers: [ProjectContainer]

        package init(
            composeFile: ComposeFile,
            projectName: String,
            composeDirectory: URL,
            activeProfiles: Set<String>,
            scaleOverrides: [String: Int],
            serviceFilter: Set<String>?,
            containers: [ProjectContainer]
        ) {
            self.composeFile = composeFile
            self.projectName = projectName
            self.composeDirectory = composeDirectory
            self.activeProfiles = activeProfiles
            self.scaleOverrides = scaleOverrides
            self.serviceFilter = serviceFilter
            self.containers = containers
        }
    }

    package static func buildConfiguration(context: BuildContext) throws -> Configuration {
        let activeServices = try ProfileFilter.activeServices(
            from: context.composeFile.services,
            activeProfiles: context.activeProfiles
        )
        let candidateNames = try candidateServiceNames(
            activeServices: activeServices,
            serviceFilter: context.serviceFilter
        )
        let allPlans = try ServicePlanner.plans(
            for: context.composeFile,
            projectName: context.projectName,
            composeDirectory: context.composeDirectory,
            activeProfiles: context.activeProfiles,
            scaleOverrides: context.scaleOverrides
        )
        let watched = try resolveWatchedServices(
            candidateNames: candidateNames,
            activeServices: activeServices,
            context: context,
            plansByService: Dictionary(grouping: allPlans, by: \.serviceName),
            containersByService: Dictionary(grouping: context.containers) { $0.serviceName ?? "" }
        )
        guard !watched.isEmpty else {
            throw ComposeError.invalidField(
                "develop.watch",
                reason: "no services with develop.watch rules are running. "
                    + "Start the project with compose up, then run compose watch."
            )
        }
        return Configuration(
            projectName: context.projectName,
            composeDirectory: context.composeDirectory,
            services: watched
        )
    }

    private static func candidateServiceNames(
        activeServices: [String: ComposeService],
        serviceFilter: Set<String>?
    ) throws -> [String] {
        if let serviceFilter {
            for name in serviceFilter where activeServices[name] == nil {
                throw ComposeError.undefinedService(service: name)
            }
            return serviceFilter.sorted().filter { activeServices[$0] != nil }
        }
        return activeServices.keys.sorted().filter { name in
            guard let develop = activeServices[name]?.develop else { return false }
            return !develop.watch.isEmpty
        }
    }

    private static func resolveWatchedServices(
        candidateNames: [String],
        activeServices: [String: ComposeService],
        context: BuildContext,
        plansByService: [String: [ServicePlan]],
        containersByService: [String: [ProjectContainer]]
    ) throws -> [WatchedService] {
        var watched: [WatchedService] = []
        for serviceName in candidateNames {
            guard let service = activeServices[serviceName] else { continue }
            guard let develop = service.develop, !develop.watch.isEmpty else {
                if context.serviceFilter != nil {
                    throw ComposeError.invalidField(
                        "develop.watch",
                        reason: "service '\(serviceName)' has no develop.watch rules"
                    )
                }
                continue
            }
            let rules = try WatchPathValidator.validateRules(
                serviceName: serviceName,
                develop: develop,
                composeDirectory: service.projectDirectory(orDefault: context.composeDirectory)
            )
            guard !rules.isEmpty else { continue }

            let serviceContainers = containersByService[serviceName, default: []]
            guard serviceContainers.contains(where: { $0.status == .running }) else {
                throw ComposeError.serviceNotRunning(
                    service: serviceName,
                    state: serviceContainers.isEmpty
                        ? "not started"
                        : ProjectStatus.formatState(serviceContainers[0].status)
                )
            }

            watched.append(
                WatchedService(
                    serviceName: serviceName,
                    rules: rules,
                    plans: plansByService[serviceName, default: []],
                    containers: serviceContainers
                )
            )
        }
        return watched
    }
}
