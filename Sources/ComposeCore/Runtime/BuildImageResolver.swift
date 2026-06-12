import Foundation

package enum BuildImageResolver {
    package static func resolvedImageTag(
        projectName: String,
        serviceName: String,
        service: ComposeService
    ) throws -> String {
        if let image = service.image, !image.isEmpty {
            return image
        }
        guard service.build != nil else {
            throw ComposeError.missingImage(service: serviceName)
        }
        return "\(projectName)_\(serviceName)"
    }

    package static func servicesNeedingBuild(
        from services: [String: ComposeService]
    ) -> [(name: String, service: ComposeService)] {
        services
            .filter { $0.value.build != nil }
            .sorted { $0.key < $1.key }
            .map { (name: $0.key, service: $0.value) }
    }

    package static func withResolvedImages(
        projectName: String,
        services: [String: ComposeService]
    ) throws -> [String: ComposeService] {
        var resolved: [String: ComposeService] = [:]
        resolved.reserveCapacity(services.count)
        for (serviceName, service) in services {
            let tag = try resolvedImageTag(
                projectName: projectName,
                serviceName: serviceName,
                service: service
            )
            resolved[serviceName] = service.withResolvedImage(tag)
        }
        return resolved
    }
}
