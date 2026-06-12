import ComposeCore
import Foundation

extension TestRunner {
    mutating func runProfileResolutionTests() throws {
        try runProfileResolutionParseTests()
        try runProfileResolutionIntegrationTests()
        try runProfileResolutionDownOrphanTests()
    }

    private mutating func runProfileResolutionParseTests() throws {
        let empty = ProfileResolution.resolve(cliProfiles: [], environment: [:])
        expect(empty.activeProfiles.isEmpty, "unset env and no CLI yields empty active profiles")
        expect(!empty.profileFilterRequested, "unset env and no CLI does not request profile filter")
        expect(!empty.tearsDownAll, "unset env and no CLI does not tear down all")

        let envDebug = ProfileResolution.resolve(
            cliProfiles: [],
            environment: [ProfileResolution.environmentVariableName: "debug"]
        )
        expect(envDebug.activeProfiles == ["debug"], "COMPOSE_PROFILES=debug activates debug")
        expect(envDebug.profileFilterRequested, "COMPOSE_PROFILES=debug requests profile filter")
        expect(!envDebug.tearsDownAll, "COMPOSE_PROFILES=debug does not tear down all")

        let envMulti = ProfileResolution.resolve(
            cliProfiles: [],
            environment: [ProfileResolution.environmentVariableName: "debug, metrics"]
        )
        expect(envMulti.activeProfiles == ["debug", "metrics"], "COMPOSE_PROFILES trims and splits profiles")

        let envSparse = ProfileResolution.resolve(
            cliProfiles: [],
            environment: [ProfileResolution.environmentVariableName: ",,debug,"]
        )
        expect(envSparse.activeProfiles == ["debug"], "COMPOSE_PROFILES omits empty segments")

        let merged = ProfileResolution.resolve(
            cliProfiles: ["metrics"],
            environment: [ProfileResolution.environmentVariableName: "debug"]
        )
        expect(merged.activeProfiles == ["debug", "metrics"], "CLI --profile unions with COMPOSE_PROFILES")

        let envWildcard = ProfileResolution.resolve(
            cliProfiles: [],
            environment: [ProfileResolution.environmentVariableName: "*"]
        )
        expect(envWildcard.tearsDownAll, "COMPOSE_PROFILES=* tears down all")
        expect(envWildcard.profileFilterRequested, "COMPOSE_PROFILES=* requests profile filter")

        let cliWildcardWithEnv = ProfileResolution.resolve(
            cliProfiles: [ProfileFilter.allProfilesWildcard],
            environment: [ProfileResolution.environmentVariableName: "debug"]
        )
        expect(cliWildcardWithEnv.tearsDownAll, "CLI * with env profile tears down all")
        expect(cliWildcardWithEnv.activeProfiles == ["debug"], "wildcard excluded from active profiles")

        let blankEnv = ProfileResolution.resolve(
            cliProfiles: [],
            environment: [ProfileResolution.environmentVariableName: "   "]
        )
        expect(blankEnv.activeProfiles.isEmpty, "whitespace-only COMPOSE_PROFILES is ignored")
        expect(!blankEnv.profileFilterRequested, "whitespace-only COMPOSE_PROFILES does not filter")
    }

    private mutating func runProfileResolutionIntegrationTests() throws {
        let fixture = try ComposeParser.parse(fileURL: Self.fixtureURL("profiles-compose.yml"))
        let fixturesDirectory = Self.fixtureURL("profiles-compose.yml").deletingLastPathComponent()

        let envOnly = ProfileResolution.resolve(
            cliProfiles: [],
            environment: [ProfileResolution.environmentVariableName: "debug"]
        )
        let filter = try ProfileFilter.queryServiceFilter(
            composeFile: fixture,
            activeProfiles: envOnly.activeProfiles,
            positionalServices: [],
            profileFilterRequested: envOnly.profileFilterRequested
        )
        expect(filter == ["web", "db", "debugger"], "env-only profile filter narrows query services")

        let layers = try ServicePlanner.startupLayers(
            for: fixture,
            projectName: "demo",
            composeDirectory: fixturesDirectory,
            activeProfiles: envOnly.activeProfiles
        )
        let names = Set(layers.flatMap { $0 }.map(\.serviceName))
        expect(names == ["web", "db", "debugger"], "env-only COMPOSE_PROFILES includes debugger on up")
    }

    private mutating func runProfileResolutionDownOrphanTests() throws {
        let discovered = [
            DiscoveredContainer(name: "demo_web", serviceName: "web"),
            DiscoveredContainer(name: "demo_debugger", serviceName: "debugger"),
            DiscoveredContainer(name: "demo_metrics", serviceName: "metrics")
        ]

        let envDebug = ProfileResolution.resolve(
            cliProfiles: [],
            environment: [ProfileResolution.environmentVariableName: "debug"]
        )
        expectComposeError(
            "env-only COMPOSE_PROFILES down -p without compose file errors",
            matching: { if case .profileFilterRequiresComposeFile = $0 { true } else { false } },
            body: {
                _ = try ProfileFilter.downServiceFilter(
                    composeFile: nil,
                    activeProfiles: envDebug.activeProfiles,
                    tearsDownAll: envDebug.tearsDownAll
                )
            }
        )

        let profilesFixture = try ComposeParser.parse(fileURL: Self.fixtureURL("profiles-compose.yml"))
        let serviceFilter = try ProfileFilter.downServiceFilter(
            composeFile: profilesFixture,
            activeProfiles: envDebug.activeProfiles,
            tearsDownAll: envDebug.tearsDownAll
        )
        let narrowed = ProjectStatus.filteredDiscoveredContainers(from: discovered, filter: serviceFilter)
        expect(
            Set(narrowed.map(\.name)) == ["demo_web", "demo_debugger"],
            "env-only COMPOSE_PROFILES down narrows teardown to active profiles"
        )

        let envWildcard = ProfileResolution.resolve(
            cliProfiles: [],
            environment: [ProfileResolution.environmentVariableName: "*"]
        )
        let wildcardFilter = try ProfileFilter.downServiceFilter(
            composeFile: nil,
            activeProfiles: envWildcard.activeProfiles,
            tearsDownAll: envWildcard.tearsDownAll
        )
        expect(wildcardFilter == nil, "env-only COMPOSE_PROFILES=* down -p skips compose file filter")
        let allContainers = ProjectStatus.filteredDiscoveredContainers(from: discovered, filter: wildcardFilter)
        expect(allContainers.count == 3, "env-only COMPOSE_PROFILES=* down -p keeps all containers")

        let profileOrphans = OrphanRemoval.orphans(
            in: discovered,
            composeFile: profilesFixture,
            policy: .duringDown(
                profileFilterRequested: envDebug.profileFilterRequested,
                tearsDownAll: envDebug.tearsDownAll,
                activeProfiles: envDebug.activeProfiles
            )
        )
        expect(
            profileOrphans.map(\.name) == ["demo_metrics"],
            "env-only COMPOSE_PROFILES orphan policy matches CLI --profile debug"
        )

        expectComposeError(
            "env-only COMPOSE_PROFILES ps filter without compose file errors",
            matching: { if case .profileFilterRequiresComposeFile = $0 { true } else { false } },
            body: {
                _ = try ProfileFilter.queryServiceFilter(
                    composeFile: nil,
                    activeProfiles: envDebug.activeProfiles,
                    positionalServices: [],
                    profileFilterRequested: envDebug.profileFilterRequested
                )
            }
        )
    }
}
