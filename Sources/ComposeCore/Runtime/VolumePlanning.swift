import ContainerResource
import Foundation

/// Pure validation and naming for compose named volumes.
///
/// Volume create/delete side effects live in `VolumeRunner`; run-argument
/// emission lives in `ServiceRunMapping`. This module never calls either.
package enum VolumePlanning {
    package struct Plan: Sendable, Equatable {
        package let logicalName: String
        /// Project-scoped runtime name: `{project}_{logical}`.
        package let runtimeName: String

        package init(logicalName: String, runtimeName: String) {
            self.logicalName = logicalName
            self.runtimeName = runtimeName
        }
    }

    package static func runtimeVolumeName(projectName: String, volumeName: String) throws -> String {
        let runtimeName = "\(projectName)_\(volumeName)"
        guard VolumeResource.nameValid(runtimeName) else {
            throw ComposeError.invalidVolumeName(volume: volumeName, runtimeName: runtimeName)
        }
        return runtimeName
    }

    /// Rejects service named-volume refs missing from root `volumes:`.
    package static func validate(composeFile: ComposeFile, activeServiceNames: Set<String>) throws {
        for serviceName in activeServiceNames.sorted() {
            guard let service = composeFile.services[serviceName] else { continue }
            for logicalName in referencedNamedVolumes(service: service) where composeFile.volumes[logicalName] == nil {
                throw ComposeError.undefinedVolume(service: serviceName, volume: logicalName)
            }
        }
    }

    /// Unique named volumes referenced by active services, sorted by logical name.
    package static func plans(
        composeFile: ComposeFile,
        projectName: String,
        activeServiceNames: Set<String>
    ) throws -> [Plan] {
        try validate(composeFile: composeFile, activeServiceNames: activeServiceNames)
        var referenced: Set<String> = []
        for serviceName in activeServiceNames {
            guard let service = composeFile.services[serviceName] else { continue }
            referenced.formUnion(referencedNamedVolumes(service: service))
        }
        return try referenced.sorted().map { logicalName in
            Plan(
                logicalName: logicalName,
                runtimeName: try runtimeVolumeName(projectName: projectName, volumeName: logicalName)
            )
        }
    }

    package static func referencedNamedVolumes(service: ComposeService) -> Set<String> {
        var names: Set<String> = []
        for volume in service.volumes {
            guard let spec = try? ComposeBindingKeys.parseVolumeSpec(volume),
                  case .named(let logicalName) = spec.source
            else { continue }
            names.insert(logicalName)
        }
        return names
    }
}
