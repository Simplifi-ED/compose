import Foundation

public struct PlannedFileMount: Sendable, Equatable {
    public let kind: ComposeFileMountKind
    public let definitionName: String
    public let sourcePath: URL
    public let containerTarget: String
}

package enum ComposeFileMountResolver {
    static func validate(composeFile: ComposeFile) throws {
        for (_, service) in composeFile.services {
            try validateServiceReferences(
                mounts: service.configs,
                definitions: composeFile.configs,
                kind: .config
            )
            try validateServiceReferences(
                mounts: service.secrets,
                definitions: composeFile.secrets,
                kind: .secret
            )
        }
        for definition in composeFile.configs.values {
            _ = try resolveDefinitionPath(definition, kind: .config)
        }
        for definition in composeFile.secrets.values {
            _ = try resolveDefinitionPath(definition, kind: .secret)
        }
    }

    static func plannedMounts(
        for service: ComposeService,
        composeFile: ComposeFile
    ) throws -> [PlannedFileMount] {
        let configMounts = try resolvePlannedMounts(
            serviceMounts: service.configs,
            definitions: composeFile.configs,
            kind: .config
        )
        let secretMounts = try resolvePlannedMounts(
            serviceMounts: service.secrets,
            definitions: composeFile.secrets,
            kind: .secret
        )
        return configMounts + secretMounts
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
        let resolved: URL
        switch try BindMountPathResolver.resolveHostPath(definition.file, relativeTo: root) {
        case .projectRelative(let url), .absoluteExternal(let url):
            resolved = url
        }
        guard FileManager.default.fileExists(atPath: resolved.path) else {
            throw ComposeError.resourceFileNotFound(path: definition.file, kind: kind)
        }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory), isDirectory.boolValue {
            throw ComposeError.invalidField(
                kind.rootFieldName,
                reason: "file '\(definition.file)' must point to a regular file, not a directory"
            )
        }
        return resolved
    }

    package static func readOnlyVolumeFlag(hostPath: String, containerPath: String) -> String {
        "\(hostPath):\(containerPath):ro"
    }
}
