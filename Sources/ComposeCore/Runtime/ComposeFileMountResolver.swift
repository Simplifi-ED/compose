import Foundation

public struct PlannedFileMount: Sendable, Equatable {
    public let kind: ComposeFileMountKind
    public let definitionName: String
    package let sourceRelativePath: String
    package let resolutionRoot: URL
    public let containerTarget: String
}

package enum ComposeFileMountResolver {
    package static func validate(
        composeFile: ComposeFile,
        activeServiceNames: Set<String>
    ) throws {
        var referencedResources: [ComposeFileMountKind: Set<String>] = [
            .config: [],
            .secret: []
        ]
        for serviceName in activeServiceNames {
            guard let service = composeFile.services[serviceName] else { continue }
            for kind in ComposeFileMountKind.allCases {
                let mounts = service.mounts(for: kind)
                let definitions = composeFile.resources(for: kind)
                for mount in mounts {
                    _ = try requireDefinition(
                        name: mount.source,
                        kind: kind,
                        definitions: definitions
                    )
                    referencedResources[kind, default: []].insert(mount.source)
                }
            }
            try validateUniqueTargets(serviceName: serviceName, service: service)
        }
        for kind in ComposeFileMountKind.allCases {
            let definitions = composeFile.resources(for: kind)
            for name in referencedResources[kind, default: []] {
                guard let definition = definitions[name],
                      let root = definition.resolutionRoot
                else { continue }
                _ = try verifiedSourceFile(
                    relativePath: definition.file,
                    resolutionRoot: root,
                    kind: kind
                )
            }
        }
    }

    static func plannedMounts(
        for service: ComposeService,
        composeFile: ComposeFile
    ) throws -> [PlannedFileMount] {
        try ComposeFileMountKind.allCases.flatMap { kind in
            try resolvePlannedMounts(
                serviceMounts: service.mounts(for: kind),
                definitions: composeFile.resources(for: kind),
                kind: kind
            )
        }
    }

    package static func verifiedSourceFile(
        relativePath: String,
        resolutionRoot: URL,
        kind: ComposeFileMountKind
    ) throws -> URL {
        let definition = ComposeFileResource(file: relativePath, resolutionRoot: resolutionRoot)
        let url = try resolveDefinitionPathForPlanning(definition, kind: kind)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ComposeError.resourceFileNotFound(path: relativePath, kind: kind)
        }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            throw ComposeError.invalidField(
                kind.rootFieldName,
                reason: "file '\(relativePath)' must point to a regular file, not a directory"
            )
        }
        return url
    }

    private static func requireDefinition(
        name: String,
        kind: ComposeFileMountKind,
        definitions: [String: ComposeFileResource]
    ) throws -> ComposeFileResource {
        guard let definition = definitions[name] else {
            throw ComposeError.undefinedResource(name: name, kind: kind)
        }
        return definition
    }

    private static func validateUniqueTargets(
        serviceName: String,
        service: ComposeService
    ) throws {
        var seenTargets: Set<String> = []
        for kind in ComposeFileMountKind.allCases {
            for mount in service.mounts(for: kind) {
                let target = mount.resolvedTarget(kind: kind)
                guard seenTargets.insert(target).inserted else {
                    throw ComposeError.invalidField(
                        kind.rootFieldName,
                        reason: "service '\(serviceName)' maps multiple configs/secrets to '\(target)'"
                    )
                }
            }
        }
    }

    private static func resolvePlannedMounts(
        serviceMounts: [ComposeServiceMount],
        definitions: [String: ComposeFileResource],
        kind: ComposeFileMountKind
    ) throws -> [PlannedFileMount] {
        try serviceMounts.map { mount in
            let definition = try requireDefinition(
                name: mount.source,
                kind: kind,
                definitions: definitions
            )
            guard let root = definition.resolutionRoot else {
                throw ComposeError.invalidField(
                    kind.rootFieldName,
                    reason: "missing compose file directory for '\(definition.file)'"
                )
            }
            _ = try resolveDefinitionPathForPlanning(definition, kind: kind)
            return PlannedFileMount(
                kind: kind,
                definitionName: mount.source,
                sourceRelativePath: definition.file,
                resolutionRoot: root,
                containerTarget: mount.resolvedTarget(kind: kind)
            )
        }
    }

    private static func resolveDefinitionPathForPlanning(
        _ definition: ComposeFileResource,
        kind: ComposeFileMountKind
    ) throws -> URL {
        guard let root = definition.resolutionRoot else {
            throw ComposeError.invalidField(
                kind.rootFieldName,
                reason: "missing compose file directory for '\(definition.file)'"
            )
        }
        if definition.file.hasPrefix("/") {
            throw ComposeError.invalidField(
                kind.rootFieldName,
                reason: "absolute file paths aren't supported for \(kind.rootFieldName). "
                    + "Use a path relative to the compose file directory."
            )
        }
        let resolved = try BindMountPathResolver.resolveHostPath(
            definition.file,
            relativeTo: root,
            fieldName: kind.rootFieldName
        )
        guard case .projectRelative(let url) = resolved else {
            throw ComposeError.invalidField(
                kind.rootFieldName,
                reason: "file '\(definition.file)' must be relative to the compose file directory"
            )
        }
        return url
    }
}
