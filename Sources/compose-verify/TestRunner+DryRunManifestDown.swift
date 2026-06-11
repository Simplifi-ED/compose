import ComposeCore
import ContainerResource
import Foundation

extension TestRunner {
    mutating func runDryRunOrphanTests() throws {
        let composeFile = try ComposeParser.parse(fileURL: Self.fixtureURL("orphan-drift-compose.yml"))
        let manifest = DryRunManifest()
        let lines = dryRunManifestLines(manifest: manifest) { manifest in
            let orphans = OrphanRemoval.orphans(
                in: [
                    DiscoveredContainer(name: "demo_web", serviceName: "web"),
                    DiscoveredContainer(name: "demo_legacy", serviceName: "legacy")
                ],
                composeFile: composeFile,
                policy: .beforeUp(activeProfiles: [])
            )
            for orphan in orphans {
                await manifest.recordTeardown(orphan.name, reason: .orphan)
            }
        }
        expect(lines.count == 1, "dry-run orphan single removal")
        expect(
            lines[0] == "[DRY-RUN] stop+delete container \"demo_legacy\" reason=orphan",
            "dry-run orphan manifest line"
        )
    }

    mutating func runDryRunDownTests() throws {
        let composeFile = try ComposeParser.parse(fileURL: Self.fixtureURL("depends-compose.yml"))
        let containers = [
            DiscoveredContainer(name: "demo_web", serviceName: "web"),
            DiscoveredContainer(name: "demo_db", serviceName: "db")
        ]
        let layers = try ServicePlanner.shutdownContainerLayers(
            for: composeFile,
            containers: containers
        )
        let manifest = DryRunManifest()
        let (completed, lines) = dryRunDownResult(layers: layers, manifest: manifest)
        expect(completed, "dry-run down completes")
        expect(lines.count == 2, "dry-run down teardown lines")
        expect(
            lines[0] == "[DRY-RUN] stop+delete container \"demo_web\"",
            "dry-run down first wave"
        )
        expect(
            lines[1] == "[DRY-RUN] stop+delete container \"demo_db\"",
            "dry-run down second wave"
        )
    }

    mutating func runDryRunVolumePurgeTests() throws {
        let fixtureURL = Self.fixtureURL("volumes-purge-compose.yml")
        let composeFile = try ComposeParser.parse(fileURL: fixtureURL)
        let sharedPathContext = DownShutdown.VolumePurgeContext(
            composeFile: composeFile,
            fileURLs: [fixtureURL],
            teardownServiceNames: ["web"],
            runningServiceNames: ["cache"]
        )
        let sharedPaths = DownShutdown.previewVolumePurgePaths(context: sharedPathContext)
        expect(sharedPaths.isEmpty, "dry-run purge skips paths still used by running services")

        let purgeableContext = DownShutdown.VolumePurgeContext(
            composeFile: composeFile,
            fileURLs: [fixtureURL],
            teardownServiceNames: ["web", "cache"],
            runningServiceNames: []
        )
        let paths = DownShutdown.previewVolumePurgePaths(context: purgeableContext)
        let composeDirectory = fixtureURL.deletingLastPathComponent()
        let expectedDataPath = composeDirectory
            .appendingPathComponent("data")
            .standardizedFileURL.path
        let manifest = DryRunManifest()
        let lines = dryRunManifestLines(manifest: manifest) { manifest in
            await manifest.recordPurge(paths: paths)
        }
        expect(lines.count == 1, "dry-run purge single project-relative path")
        expect(
            lines[0] == "[DRY-RUN] purge bind-mount path \"\(expectedDataPath)\"",
            "dry-run purge manifest line"
        )
    }

    mutating func runDryRunRunTests() throws {
        let fixturesDirectory = Self.fixtureURL("minimal-compose.yml").deletingLastPathComponent()
        let service = ComposeService(
            image: "docker.io/library/alpine:latest",
            command: .string("sleep 300"),
            ports: ["18080:80"],
            environment: nil,
            containerName: nil
        )
        let composeFile = ComposeFile(name: nil, services: ["web": service])
        let plan = try ServicePlanner.runPlan(
            context: ServicePlanner.PlanningContext(
                composeFile: composeFile,
                projectName: "demo",
                composeDirectory: fixturesDirectory
            ),
            serviceName: "web",
            service: service,
            options: RunPlanOptions(
                removeContainer: true,
                commandOverride: ["echo", "hi"],
                interactive: false,
                processTerminal: false,
                nameSuffix: "abcd1234"
            )
        )
        let manifest = DryRunManifest()
        let lines = dryRunManifestLines(manifest: manifest) { manifest in
            await manifest.recordCreate(plan)
        }
        expect(lines.count == 1, "dry-run run single create line")
        expect(
            lines[0] == DryRunManifestFormatting.formatCreate(plan),
            "dry-run run create manifest"
        )
        expect(lines[0].contains("demo_web_run_abcd1234"), "dry-run run stable suffix name")
        expect(lines[0].contains("remove=true"), "dry-run run remove flag")
    }

    mutating func runDryRunExecTests() {
        let containers = [
            ProjectContainer(
                name: "demo_web_1",
                serviceName: "web",
                status: .running,
                publishedPorts: []
            )
        ]
        expectComposeError(
            "dry-run exec missing service",
            matching: { if case .serviceNotFound = $0 { true } else { false } },
            body: {
                _ = try ExecContainerResolver.resolve(
                    projectName: "demo",
                    serviceName: "missing",
                    containers: containers
                )
            }
        )

        let target = try? ExecContainerResolver.resolve(
            projectName: "demo",
            serviceName: "web",
            containers: containers
        )
        expect(target?.name == "demo_web_1", "dry-run exec resolver target")

        let manifest = DryRunManifest()
        let lines = dryRunManifestLines(manifest: manifest) { manifest in
            await manifest.recordExec(container: "demo_web_1", command: ["sh", "-c", "echo hi"])
        }
        expect(
            lines[0] == "[DRY-RUN] exec container \"demo_web_1\" command=[\"sh\", \"-c\", \"echo hi\"]",
            "dry-run exec manifest line"
        )
    }

    mutating func runDryRunPlanningValidationTests() throws {
        let composeFile = ComposeFile(
            name: nil,
            services: [
                "web": ComposeService(
                    image: nil,
                    command: .string("sleep 300"),
                    ports: [],
                    environment: nil,
                    containerName: nil
                )
            ]
        )
        let composeDirectory = Self.fixtureURL("minimal-compose.yml").deletingLastPathComponent()
        expectComposeError(
            "dry-run up rejects missing image during planning",
            matching: { if case .missingImage = $0 { true } else { false } },
            body: {
                _ = try ServicePlanner.startupLayers(
                    for: composeFile,
                    projectName: "demo",
                    composeDirectory: composeDirectory,
                    activeProfiles: [],
                    scaleOverrides: [:]
                )
            }
        )

        let manifest = DryRunManifest()
        let lines = blockingAwait { await manifest.sortedLines() }
        expect(lines.isEmpty, "dry-run manifest empty when planning fails before orchestration")
    }
}
