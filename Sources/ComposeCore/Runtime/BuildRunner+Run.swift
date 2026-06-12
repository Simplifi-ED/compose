import Foundation

extension BuildRunner {
    /// Build plans for `compose run`: target service plus transitive `depends_on` services that define `build:`.
    package static func runBuildPlans(
        targetServiceName: String,
        composeFile: ComposeFile,
        projectName: String,
        composeDirectory: URL
    ) throws -> [Plan] {
        guard composeFile.services[targetServiceName] != nil else {
            throw ComposeError.undefinedService(service: targetServiceName)
        }
        let closure = try buildDependencyClosure(
            for: targetServiceName,
            in: composeFile.services
        )
        let orderedNames = try DependencyGraph.serviceLayers(for: closure).flatMap { $0 }
        let needingBuild = orderedNames.filter { closure[$0]?.build != nil }
        guard !needingBuild.isEmpty else { return [] }

        try BuildValidator.validate(
            composeFile: composeFile,
            projectName: projectName,
            composeDirectory: composeDirectory,
            activeServiceNames: Set(needingBuild)
        )

        return try needingBuild.map { serviceName in
            try makePlan(
                serviceName: serviceName,
                service: closure[serviceName]!,
                projectName: projectName,
                composeDirectory: composeDirectory
            )
        }
    }

    private static func buildDependencyClosure(
        for targetServiceName: String,
        in services: [String: ComposeService]
    ) throws -> [String: ComposeService] {
        var closure: [String: ComposeService] = [:]
        var pending = [targetServiceName]
        while let serviceName = pending.popLast() {
            guard let service = services[serviceName] else {
                throw ComposeError.undefinedService(service: serviceName)
            }
            guard closure[serviceName] == nil else { continue }
            closure[serviceName] = service
            for dependency in service.dependsOn.map(\.service) where closure[dependency] == nil {
                pending.append(dependency)
            }
        }
        return closure
    }
}
