import Foundation

package enum ProfileFilter {
    /// Wildcard token for `down --profile "*"` — tears down all project containers.
    package static let allProfilesWildcard = "*"

    package static func isEligible(_ service: ComposeService, activeProfiles: Set<String>) -> Bool {
        if service.profiles.isEmpty {
            return true
        }
        return !activeProfiles.isDisjoint(with: service.profiles)
    }

    package static func activeServices(
        from services: [String: ComposeService],
        activeProfiles: Set<String>
    ) throws -> [String: ComposeService] {
        let names = matchingServiceNames(
            from: services,
            activeProfiles: activeProfiles,
            includeAll: false
        )
        let active = Dictionary(uniqueKeysWithValues: names.map { ($0, services[$0]!) })

        for (serviceName, service) in active {
            for dependency in service.dependsOn {
                guard let dependencyService = services[dependency.service] else {
                    continue
                }
                if active[dependency.service] == nil {
                    throw ComposeError.profileExcludedDependency(
                        service: serviceName,
                        dependency: dependency.service,
                        requiredProfiles: dependencyService.profiles
                    )
                }
            }
        }

        return active
    }

    package static func matchingServiceNames(
        from services: [String: ComposeService],
        activeProfiles: Set<String>,
        includeAll: Bool
    ) -> Set<String> {
        if includeAll {
            return Set(services.keys)
        }
        return Set(services.filter { isEligible($0.value, activeProfiles: activeProfiles) }.keys)
    }

    /// Service-name filter for `ps`, `logs`, and `top`.
    ///
    /// Returns `nil` when every project container should be included.
    package static func queryServiceFilter(
        composeFile: ComposeFile?,
        activeProfiles: Set<String>,
        positionalServices: [String],
        profileFilterRequested: Bool
    ) throws -> Set<String>? {
        if profileFilterRequested {
            guard let composeFile else {
                throw ComposeError.profileFilterRequiresComposeFile
            }
            var filter = matchingServiceNames(
                from: composeFile.services,
                activeProfiles: activeProfiles,
                includeAll: false
            )
            if !positionalServices.isEmpty {
                filter = filter.intersection(Set(positionalServices))
            }
            return filter
        }

        if positionalServices.isEmpty {
            return nil
        }
        return Set(positionalServices)
    }

    /// Service-name filter for `down` when `--profile` is passed.
    ///
    /// Returns `nil` when every project container should be stopped (`*` wildcard or no narrowing).
    package static func downServiceFilter(
        composeFile: ComposeFile?,
        activeProfiles: Set<String>,
        tearsDownAll: Bool
    ) throws -> Set<String>? {
        if tearsDownAll {
            return nil
        }
        guard let composeFile else {
            throw ComposeError.profileFilterRequiresComposeFile
        }
        return matchingServiceNames(
            from: composeFile.services,
            activeProfiles: activeProfiles,
            includeAll: false
        )
    }
}
