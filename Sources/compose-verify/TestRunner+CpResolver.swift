import ComposeCore
import Foundation

extension TestRunner {
    static let cpRunningWebOne = ProjectContainer(
        name: "demo_web_1",
        serviceName: "web",
        status: .running,
        publishedPorts: []
    )
    static let cpRunningWebTwo = ProjectContainer(
        name: "demo_web_2",
        serviceName: "web",
        status: .running,
        publishedPorts: []
    )
    static let cpRunningDb = ProjectContainer(
        name: "demo_db_1",
        serviceName: "db",
        status: .running,
        publishedPorts: []
    )

    mutating func runCpResolverTests() {
        runCpResolverSuccessTests()
        runCpResolverErrorTests()
    }

    private mutating func runCpResolverSuccessTests() {
        runCpResolverDefaultSuccessTest()
        runCpResolverScaledSuccessTests()
    }

    private mutating func runCpResolverDefaultSuccessTest() {
        do {
            let resolved = try CpContainerResolver.resolve(
                projectName: "demo",
                serviceName: "web",
                containers: [Self.cpRunningWebOne, Self.cpRunningDb],
                index: nil,
                all: false
            )
            expect(resolved.map(\.name) == ["demo_web_1"], "resolver default picks single running replica")
        } catch {
            fputs("FAIL: resolver should succeed for single replica: \(error)\n", stderr)
            failures += 1
        }
    }

    private mutating func runCpResolverScaledSuccessTests() {
        do {
            let indexed = try CpContainerResolver.resolve(
                projectName: "demo",
                serviceName: "web",
                containers: [Self.cpRunningWebOne, Self.cpRunningWebTwo],
                index: 2,
                all: false
            )
            expect(indexed.map(\.name) == ["demo_web_2"], "resolver --index selects named replica")
        } catch {
            fputs("FAIL: indexed resolver should succeed: \(error)\n", stderr)
            failures += 1
        }

        do {
            let allReplicas = try CpContainerResolver.resolve(
                projectName: "demo",
                serviceName: "web",
                containers: [Self.cpRunningWebOne, Self.cpRunningWebTwo, Self.cpRunningDb],
                index: nil,
                all: true
            )
            expect(
                allReplicas.map(\.name) == ["demo_web_1", "demo_web_2"],
                "resolver --all returns running replicas"
            )
        } catch {
            fputs("FAIL: --all resolver should succeed: \(error)\n", stderr)
            failures += 1
        }
    }

    private mutating func runCpResolverErrorTests() {
        expectComposeError(
            "ambiguous service",
            matching: {
                if case .ambiguousService(service: "web", containers: let names) = $0 {
                    return Set(names) == ["demo_web_1", "demo_web_2"]
                }
                return false
            },
            body: {
                _ = try CpContainerResolver.resolve(
                    projectName: "demo",
                    serviceName: "web",
                    containers: [Self.cpRunningWebOne, Self.cpRunningWebTwo],
                    index: nil,
                    all: false
                )
            }
        )

        expectComposeError(
            "replica not found",
            matching: {
                if case .replicaNotFound(service: "web", index: 3, project: "demo") = $0 {
                    true
                } else {
                    false
                }
            },
            body: {
                _ = try CpContainerResolver.resolve(
                    projectName: "demo",
                    serviceName: "web",
                    containers: [Self.cpRunningWebOne],
                    index: 3,
                    all: false
                )
            }
        )
    }
}
