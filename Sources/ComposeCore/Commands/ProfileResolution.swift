import Foundation

package enum ProfileResolution {
    package static let environmentVariableName = "COMPOSE_PROFILES"

    package struct Result: Sendable {
        package let activeProfiles: Set<String>
        package let profileFilterRequested: Bool
        package let tearsDownAll: Bool
    }

    package static func resolve(
        cliProfiles: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Result {
        let envProfiles = profilesFromEnvironment(environment)
        let combined = envProfiles + cliProfiles
        let tearsDownAll = combined.contains(ProfileFilter.allProfilesWildcard)
        let activeProfiles = Set(
            combined.filter { $0 != ProfileFilter.allProfilesWildcard }
        )
        let profileFilterRequested = !envProfiles.isEmpty || !cliProfiles.isEmpty
        return Result(
            activeProfiles: activeProfiles,
            profileFilterRequested: profileFilterRequested,
            tearsDownAll: tearsDownAll
        )
    }

    package static func profilesFromEnvironment(
        _ environment: [String: String]
    ) -> [String] {
        guard let raw = environment[environmentVariableName] else {
            return []
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }
        return trimmed.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
