import ComposeCore
import Foundation

extension TestRunner {
    mutating func runOrphanTests() throws {
        try runOrphanDetectionTests()
        try runOrphanUnionTests()
        try runOrphanShutdownLayerTests()
    }

    mutating func runOrphanDetectionTests() throws {
        let driftFixture = try ComposeParser.parse(fileURL: Self.fixtureURL("orphan-drift-compose.yml"))
        let containers = [
            DiscoveredContainer(name: "demo_web", serviceName: "web"),
            DiscoveredContainer(name: "demo_api", serviceName: "api"),
            DiscoveredContainer(name: "legacy", serviceName: nil)
        ]

        let yamlOrphans = OrphanRemoval.orphans(
            in: containers,
            composeFile: driftFixture,
            policy: .yamlOnly
        )
        expect(yamlOrphans.map(\.name) == ["demo_api", "legacy"], "yaml-removed and unlabeled containers are orphans")

        let profilesFixture = try ComposeParser.parse(fileURL: Self.fixtureURL("profiles-compose.yml"))
        let profiledContainers = [
            DiscoveredContainer(name: "demo_web", serviceName: "web"),
            DiscoveredContainer(name: "demo_debugger", serviceName: "debugger"),
            DiscoveredContainer(name: "demo_metrics", serviceName: "metrics")
        ]
        let profileOrphans = OrphanRemoval.orphans(
            in: profiledContainers,
            composeFile: profilesFixture,
            policy: .duringDown(
                profileFilterRequested: true,
                tearsDownAll: false,
                activeProfiles: ["debug"]
            )
        )
        expect(profileOrphans.map(\.name) == ["demo_metrics"], "profile-skipped service is orphan when flag set")

        let noProfileOrphans = OrphanRemoval.orphans(
            in: profiledContainers,
            composeFile: profilesFixture,
            policy: .yamlOnly
        )
        expect(noProfileOrphans.isEmpty, "profile-skipped service is not orphan without flag")

        let otherProject = [
            DiscoveredContainer(name: "other_web", serviceName: "web")
        ]
        let scopedOrphans = OrphanRemoval.orphans(
            in: otherProject,
            composeFile: driftFixture,
            policy: .yamlOnly
        )
        expect(scopedOrphans.isEmpty, "containers outside discovery input are not auto-included")
    }

    mutating func runOrphanUnionTests() throws {
        let selected = [
            DiscoveredContainer(name: "demo_web", serviceName: "web")
        ]
        let orphans = [
            DiscoveredContainer(name: "demo_api", serviceName: "api"),
            DiscoveredContainer(name: "legacy", serviceName: nil)
        ]
        let merged = OrphanRemoval.mergingContainers(selected, with: orphans)
        expect(
            merged.map(\.name) == ["demo_api", "demo_web", "legacy"],
            "merge combines selected and orphan containers"
        )
    }

    mutating func runOrphanShutdownLayerTests() throws {
        let dependsFixture = try ComposeParser.parse(fileURL: Self.fixtureURL("depends-compose.yml"))
        let containers = [
            DiscoveredContainer(name: "demo_web", serviceName: "web"),
            DiscoveredContainer(name: "demo_db", serviceName: "db"),
            DiscoveredContainer(name: "legacy", serviceName: nil)
        ]
        let containerShutdown = try ServicePlanner.shutdownContainerLayers(
            for: dependsFixture,
            containers: containers
        )
        expect(containerShutdown.count == 3, "shutdown container layers include orphan wave")
        expect(containerShutdown[2].map(\.name) == ["legacy"], "shutdown orphan final wave")
    }
}
