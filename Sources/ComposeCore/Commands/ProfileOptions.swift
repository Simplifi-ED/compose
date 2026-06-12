import ArgumentParser

public struct ProfileOptions: ParsableArguments {
    public init() {}

    @Option(
        name: .customLong("profile"),
        help: """
        Profile to enable or filter by. Repeat for multiple profiles (OR). Also set COMPOSE_PROFILES \
        (comma-separated); CLI flags add to the env set. On up, enables matching services; services \
        without profiles always start. On ps, logs, top, config, watch, and down, limits to services \
        without profiles plus matching services. On down, pass "*" to stop every project container.
        """
    )
    var profiles: [String] = []

    package var resolution: ProfileResolution.Result {
        ProfileResolution.resolve(cliProfiles: profiles)
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
