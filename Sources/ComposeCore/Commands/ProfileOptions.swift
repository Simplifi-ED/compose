import ArgumentParser

public struct ProfileOptions: ParsableArguments {
    public init() {
        resolutionCache = ResolutionCache()
    }

    @Option(
        name: .customLong("profile"),
        help: """
        Profile to enable or filter by. Repeat for multiple profiles (OR). Also set COMPOSE_PROFILES \
        (comma-separated); CLI flags add to the env set. On up, enables matching services; services \
        without profiles always start. On ps, logs, top, and down, limits to services without profiles \
        plus matching services. On down, pass "*" to stop every project container.
        """
    )
    var profiles: [String] = []

    private final class ResolutionCache: @unchecked Sendable {
        private var lastProfiles: [String]?
        private var cached: ProfileResolution.Result?

        func resolve(cliProfiles: [String]) -> ProfileResolution.Result {
            if lastProfiles == cliProfiles, let cached {
                return cached
            }
            lastProfiles = cliProfiles
            let result = ProfileResolution.resolve(cliProfiles: cliProfiles)
            cached = result
            return result
        }
    }

    private let resolutionCache: ResolutionCache

    private enum CodingKeys: String, CodingKey {
        case profiles
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profiles = try container.decodeIfPresent([String].self, forKey: .profiles) ?? []
        resolutionCache = ResolutionCache()
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(profiles, forKey: .profiles)
    }

    private var resolution: ProfileResolution.Result {
        resolutionCache.resolve(cliProfiles: profiles)
    }

    public var activeProfileSet: Set<String> {
        resolution.activeProfiles
    }

    public var profileFilterRequested: Bool {
        resolution.profileFilterRequested
    }

    public var tearsDownAll: Bool {
        resolution.tearsDownAll
    }
}
