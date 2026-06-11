import Foundation

public struct PlannedFileMount: Sendable, Equatable {
    public let kind: ComposeFileMountKind
    public let definitionName: String
    public let sourcePath: URL
    public let containerTarget: String
}

package enum ComposeFileMountResolver {
    static func validate(composeFile: ComposeFile) throws {
        for (serviceName, service) in composeFile.services {
            for kind in ComposeFileMountKind.allCases {
                let mounts = service.mounts(for: kind)
                let definitions = composeFile.resources(for: kind)
                try validateServiceReferences(
                    mounts: mounts,
                    definitions: definitions,
                    kind: kind
                )
            }
            try validateUniqueTargets(serviceName: serviceName, service: service)
        }
        for kind in ComposeFileMountKind.allCases {
            for definition in composeFile.resources(for: kind).values {
                _ = try resolveDefinitionPath(definition, kind: kind)
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

    private static func validateServiceReferences(
        mounts: [ComposeServiceMount],
        definitions: [String: ComposeFileResource],
        kind: ComposeFileMountKind
    ) throws {
        for mount in mounts {
            guard definitions[mount.source] != nil else {
                throw ComposeError.undefinedResource(name: mount.source, kind: kind)
            }
        }
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
            guard let definition = definitions[mount.source] else {
                throw ComposeError.undefinedResource(name: mount.source, kind: kind)
            }
            let sourcePath = try resolveDefinitionPath(definition, kind: kind)
            return PlannedFileMount(
                kind: kind,
                definitionName: mount.source,
                sourcePath: sourcePath,
                containerTarget: mount.resolvedTarget(kind: kind)
            )
        }
    }

    private static func resolveDefinitionPath(
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
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ComposeError.resourceFileNotFound(path: definition.file, kind: kind)
        }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            throw ComposeError.invalidField(
                kind.rootFieldName,
                reason: "file '\(definition.file)' must point to a regular file, not a directory"
            )
        }
        return url
    }

    package static func readOnlyVolumeFlag(hostPath: String, containerPath: String) -> String {
        "\(hostPath):\(containerPath):ro"
    }
}
