import ArgumentParser

public struct ProfileOptions: ParsableArguments {
    public init() {}

    @Option(
        name: .customLong("profile"),
        help: """
        Profile to enable or filter by. Repeat for multiple profiles (OR). On up, enables matching \
        services; services without profiles always start. On ps, logs, top, and down, limits to \
        services without profiles plus matching services. On down, pass "*" to stop every project container.
        """
    )
    var profiles: [String] = []

    public var activeProfileSet: Set<String> {
        Set(profiles.filter { $0 != ProfileFilter.allProfilesWildcard })
    }

    public var profileFilterRequested: Bool { !profiles.isEmpty }

    public var tearsDownAll: Bool { profiles.contains(ProfileFilter.allProfilesWildcard) }
}
