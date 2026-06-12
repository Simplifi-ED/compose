import Foundation

package enum BuildValidator {
    package static func validate(
        composeFile: ComposeFile,
        projectName: String,
        composeDirectory: URL,
        activeServiceNames: Set<String>
    ) throws {
        for serviceName in activeServiceNames.sorted() {
            guard let service = composeFile.services[serviceName] else { continue }
            try validateService(
                serviceName: serviceName,
                service: service,
                projectName: projectName,
                composeDirectory: composeDirectory
            )
        }
    }

    package static func validateService(
        serviceName: String,
        service: ComposeService,
        projectName: String,
        composeDirectory: URL
    ) throws {
        guard let build = service.build else { return }
        let serviceDirectory = service.projectDirectory(orDefault: composeDirectory)
        _ = try resolvedContextURL(
            build: build,
            serviceName: serviceName,
            composeDirectory: serviceDirectory
        )
        try validateDockerfileIfPresent(
            build: build,
            serviceName: serviceName,
            composeDirectory: serviceDirectory
        )
        _ = try BuildImageResolver.resolvedImageTag(
            projectName: projectName,
            serviceName: serviceName,
            service: service
        )
    }

    package static func resolvedContextURL(
        build: ComposeBuild,
        serviceName: String,
        composeDirectory: URL
    ) throws -> URL {
        let resolved = try BindMountPathResolver.resolveHostPath(
            build.context,
            relativeTo: composeDirectory,
            fieldName: "build.context"
        )
        switch resolved {
        case .projectRelative(let url):
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else {
                throw ComposeError.buildContextNotFound(path: build.context, service: serviceName)
            }
            return url
        case .absoluteExternal(let url):
            let composeRoot = composeDirectory.standardizedFileURL.resolvingSymlinksInPath()
            guard BindMountPathResolver.isPathContained(url, within: composeRoot) else {
                throw ComposeError.invalidField(
                    "build.context",
                    reason: "host path '\(build.context)' resolves outside the compose file directory. "
                        + "Use a path within the project."
                )
            }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else {
                throw ComposeError.buildContextNotFound(path: build.context, service: serviceName)
            }
            return url
        }
    }

    package static func resolvedDockerfileURL(
        dockerfile: String?,
        contextURL: URL,
        serviceName: String
    ) throws -> URL? {
        guard let dockerfile, !dockerfile.isEmpty else { return nil }
        let dockerfileURL: URL
        if dockerfile.hasPrefix("/") {
            dockerfileURL = URL(fileURLWithPath: dockerfile).standardizedFileURL
        } else {
            dockerfileURL = contextURL.appendingPathComponent(dockerfile).standardizedFileURL
        }
        guard BindMountPathResolver.isPathContained(dockerfileURL, within: contextURL) else {
            throw ComposeError.invalidField(
                "build.dockerfile",
                reason: "dockerfile '\(dockerfile)' resolves outside build.context for service '\(serviceName)'"
            )
        }
        guard FileManager.default.fileExists(atPath: dockerfileURL.path) else {
            throw ComposeError.buildDockerfileNotFound(path: dockerfile, service: serviceName)
        }
        return dockerfileURL
    }

    private static func validateDockerfileIfPresent(
        build: ComposeBuild,
        serviceName: String,
        composeDirectory: URL
    ) throws {
        let contextURL = try resolvedContextURL(
            build: build,
            serviceName: serviceName,
            composeDirectory: composeDirectory
        )
        _ = try resolvedDockerfileURL(
            dockerfile: build.dockerfile,
            contextURL: contextURL,
            serviceName: serviceName
        )
    }
}
