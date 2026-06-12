import ComposeCore
import Foundation

extension TestRunner {
    mutating func runProfileTests() throws {
        try runProfileDecodeTests()
        try runProfileLayerTests()
        try runProfileErrorTests()
        try runProfileFilterTests()
        try runProfileMergeTests()
        try runProfileEmptyFilterTests()
        try runProfileDownFilterTests()
        try runProfileResolutionTests()
    }

    mutating func runProfileDecodeTests() throws {
        let fixture = try ComposeParser.parse(fileURL: Self.fixtureURL("profiles-compose.yml"))
        expect(fixture.services["debugger"]?.profiles == ["debug"], "profiles list decode")
        expect(fixture.services["web"]?.profiles == [], "profiles default empty")

        let stringFixture = try ComposeParser.parse(fileURL: Self.fixtureURL("profiles-string-compose.yml"))
        expect(stringFixture.services["debugger"]?.profiles == ["debug"], "profiles string decode")
    }

    mutating func runProfileLayerTests() throws {
        let fixturesDirectory = Self.fixtureURL("profiles-compose.yml").deletingLastPathComponent()
        let fixture = try ComposeParser.parse(fileURL: Self.fixtureURL("profiles-compose.yml"))

        let defaultLayers = try ServicePlanner.startupLayers(
            for: fixture,
            projectName: "demo",
            composeDirectory: fixturesDirectory,
            activeProfiles: []
        )
        let defaultNames = Set(defaultLayers.flatMap { $0 }.map(\.serviceName))
        expect(defaultNames == ["web", "db"], "default up excludes profiled services")

        let debugLayers = try ServicePlanner.startupLayers(
            for: fixture,
            projectName: "demo",
            composeDirectory: fixturesDirectory,
            activeProfiles: ["debug"]
        )
        let debugNames = Set(debugLayers.flatMap { $0 }.map(\.serviceName))
        expect(debugNames == ["web", "db", "debugger"], "debug profile includes debugger and unprofiled")

        let multiLayers = try ServicePlanner.startupLayers(
            for: fixture,
            projectName: "demo",
            composeDirectory: fixturesDirectory,
            activeProfiles: ["debug", "metrics"]
        )
        let multiNames = Set(multiLayers.flatMap { $0 }.map(\.serviceName))
        expect(multiNames == ["web", "db", "debugger", "metrics"], "multiple profiles OR'd")

        let orderFixture = try ComposeParser.parse(fileURL: Self.fixtureURL("profiles-order-compose.yml"))
        let orderLayers = try ServicePlanner.startupLayers(
            for: orderFixture,
            projectName: "demo",
            composeDirectory: fixturesDirectory,
            activeProfiles: ["debug"]
        )
        expect(orderLayers.count == 2, "profiled service depends_on preserves waves")
        expect(orderLayers[0].map(\.serviceName) == ["db"], "profile order wave 0")
        expect(orderLayers[1].map(\.serviceName) == ["debugger"], "profile order wave 1")

        let allProfiled = try ComposeParser.parse(fileURL: Self.fixtureURL("profiles-all-profiled-compose.yml"))
        let emptyLayers = try ServicePlanner.startupLayers(
            for: allProfiled,
            projectName: "demo",
            composeDirectory: fixturesDirectory,
            activeProfiles: []
        )
        expect(emptyLayers.isEmpty, "all profiled services with no flags yields no layers")
    }

    mutating func runProfileErrorTests() throws {
        let fixturesDirectory = Self.fixtureURL("profiles-depends-compose.yml").deletingLastPathComponent()
        let fixture = try ComposeParser.parse(fileURL: Self.fixtureURL("profiles-depends-compose.yml"))

        expectComposeError(
            "profile excluded dependency",
            matching: { if case .profileExcludedDependency = $0 { true } else { false } },
            body: {
                _ = try ServicePlanner.startupLayers(
                    for: fixture,
                    projectName: "demo",
                    composeDirectory: fixturesDirectory,
                    activeProfiles: []
                )
            }
        )
    }

    mutating func runProfileFilterTests() throws {
        let fixture = try ComposeParser.parse(fileURL: Self.fixtureURL("profiles-compose.yml"))

        let debugNames = ProfileFilter.matchingServiceNames(
            from: fixture.services,
            activeProfiles: ["debug"],
            includeAll: false
        )
        expect(debugNames == ["web", "db", "debugger"], "matching names includes unprofiled and debug")

        let metricsOnly = ProfileFilter.matchingServiceNames(
            from: fixture.services,
            activeProfiles: ["metrics"],
            includeAll: false
        )
        expect(metricsOnly == ["web", "db", "metrics"], "matching names excludes other profiles")

        let allNames = ProfileFilter.matchingServiceNames(
            from: fixture.services,
            activeProfiles: [],
            includeAll: true
        )
        expect(allNames == Set(fixture.services.keys), "includeAll returns every service")

        let filter = try ProfileFilter.queryServiceFilter(
            composeFile: fixture,
            activeProfiles: ["debug"],
            positionalServices: ["web"],
            profileFilterRequested: true
        )
        expect(filter == ["web"], "query filter intersects positional services")

        let wildcardFilter = try ProfileFilter.downServiceFilter(
            composeFile: fixture,
            activeProfiles: [],
            tearsDownAll: true
        )
        expect(wildcardFilter == nil, "wildcard down skips service filter")
    }

    mutating func runProfileMergeTests() throws {
        let mergeDirectory = Self.fixtureURL("profiles-merge/base.yml").deletingLastPathComponent()
        let merged = try ComposeParser.parse(fileURLs: [
            mergeDirectory.appendingPathComponent("base.yml"),
            mergeDirectory.appendingPathComponent("override.yml")
        ])
        expect(merged.services["web"]?.profiles == ["debug"], "merge override replaces non-empty profiles")
    }

    mutating func runProfileEmptyFilterTests() throws {
        let containers = [
            ProjectContainer(name: "demo_web", serviceName: "web", status: .running, publishedPorts: []),
            ProjectContainer(name: "demo_debugger", serviceName: "debugger", status: .running, publishedPorts: [])
        ]
        let emptyFiltered = ProjectStatus.filteredContainers(from: containers, filter: [])
        expect(emptyFiltered.isEmpty, "empty service filter matches no containers")

        let fixture = try ComposeParser.parse(fileURL: Self.fixtureURL("profiles-all-profiled-compose.yml"))
        let noMatch = try ProfileFilter.queryServiceFilter(
            composeFile: fixture,
            activeProfiles: ["typo"],
            positionalServices: [],
            profileFilterRequested: true
        )
        expect(noMatch == [], "profile with no matching services yields empty filter")

        let wildcardNoCompose = try ProfileFilter.downServiceFilter(
            composeFile: nil,
            activeProfiles: [],
            tearsDownAll: true
        )
        expect(wildcardNoCompose == nil, "wildcard down without compose file skips service filter")
    }

    mutating func runProfileDownFilterTests() throws {
        let containers = [
            DiscoveredContainer(name: "demo_web", serviceName: "web"),
            DiscoveredContainer(name: "demo_debugger", serviceName: "debugger"),
            DiscoveredContainer(name: "demo_metrics", serviceName: "metrics")
        ]
        let fixture = try ComposeParser.parse(fileURL: Self.fixtureURL("profiles-compose.yml"))
        let serviceFilter = try ProfileFilter.downServiceFilter(
            composeFile: fixture,
            activeProfiles: ["debug"],
            tearsDownAll: false
        )
        let filtered = ProjectStatus.filteredDiscoveredContainers(from: containers, filter: serviceFilter)
        expect(filtered.map(\.name) == ["demo_web", "demo_debugger"], "down subset excludes other profiles")
    }
}
