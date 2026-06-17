import ComposeCore
import Foundation

extension TestRunner {
    private static func matchesUnsupportedGPUReason(_ reason: String) -> Bool {
        reason.hasPrefix(DeployGPUPlanning.unsupportedReason)
    }

    mutating func runGPUReservationTests() throws {
        try runGPUReservationDecodeTests()
        try runGPUReservationPlanTests()
        try runGPUReservationParseErrorTests()
        try runGPUReservationConfigTests()
        try runGPUReservationMergeTests()
        try runGPUReservationDryRunTests()
    }

    private mutating func runGPUReservationDecodeTests() throws {
        let gpuFixture = try ComposeParser.parse(fileURL: Self.fixtureURL("resources-gpu-reservation-compose.yml"))
        let reservation = gpuFixture.services["web"]?.deploy?.resources?.reservations?.devices.first
        expect(reservation?.driver == "apple", "gpu reservation decode driver")
        expect(reservation?.capabilities == ["gpu"], "gpu reservation decode capabilities")
    }

    private mutating func runGPUReservationPlanTests() throws {
        try expectGPUReservationPlanError(
            "unsupported gpu reservation rejected at plan time",
            fixtureName: "resources-gpu-reservation-compose.yml",
            machineName: nil
        ) {
            if case .invalidField("deploy.resources.reservations.devices", let reason) = $0 {
                return Self.matchesUnsupportedGPUReason(reason)
                    && reason.contains("(requested for application sandbox)")
            }
            return false
        }
        try expectGPUReservationPlanError(
            "unsupported gpu reservation rejected for machine mode",
            fixtureName: "resources-gpu-reservation-compose.yml",
            machineName: "dev"
        ) {
            if case .invalidField("deploy.resources.reservations.devices", let reason) = $0 {
                return Self.matchesUnsupportedGPUReason(reason) && reason.contains("--machine dev")
            }
            return false
        }
    }

    private mutating func runGPUReservationParseErrorTests() throws {
        expectComposeError(
            "invalid gpu driver rejected during parse",
            matching: {
                if case .invalidField("deploy.resources.reservations.devices.driver", let reason) = $0 {
                    return reason.contains("only 'apple' is supported")
                }
                return false
            },
            body: {
                _ = try ComposeParser.parse(fileURL: Self.fixtureURL("resources-gpu-invalid-driver-compose.yml"))
            }
        )

        expectComposeError(
            "invalid gpu capability rejected during parse",
            matching: {
                if case .invalidField("deploy.resources.reservations.devices.capabilities", let reason) = $0 {
                    return reason.contains("only ['gpu'] is supported")
                }
                return false
            },
            body: {
                _ = try ComposeParser.parse(fileURL: Self.fixtureURL("resources-gpu-invalid-capability-compose.yml"))
            }
        )
    }

    private mutating func runGPUReservationConfigTests() throws {
        let gpuFixtureURL = Self.fixtureURL("resources-gpu-reservation-compose.yml")
        let configOutput = try ComposeConfigResolver.resolveOutput(
            fileURLs: [gpuFixtureURL],
            activeProfiles: [],
            scaleOverrides: [:]
        )
        expect(configOutput?.contains("reservations:") == true, "config output retains gpu reservations")
        expect(configOutput?.contains("driver: apple") == true, "config output retains gpu reservation driver")
        expect(configOutput?.contains("- gpu") == true, "config output retains gpu reservation capability")

        expectComposeError(
            "config quiet rejects unsupported gpu reservation",
            matching: {
                if case .invalidField("deploy.resources.reservations.devices", let reason) = $0 {
                    return Self.matchesUnsupportedGPUReason(reason)
                }
                return false
            },
            body: {
                _ = try ComposeConfigResolver.resolveOutput(
                    fileURLs: [gpuFixtureURL],
                    activeProfiles: [],
                    scaleOverrides: [:],
                    quiet: true
                )
            }
        )
    }

    private mutating func runGPUReservationMergeTests() throws {
        try runGPUReservationMergeAddDeviceTests()
        try runGPUReservationMergePreserveBaseTests()
        try runGPUReservationMergeClearBaseTests()
    }

    private mutating func runGPUReservationMergeAddDeviceTests() throws {
        let tempDir = try Self.makeGPUReservationMergeDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let basePath = tempDir.appendingPathComponent("base.yml")
        try """
        services:
          web:
            image: docker.io/library/alpine:3.24
            command: sleep 300
            deploy:
              resources:
                limits:
                  cpus: "2"
        """.write(to: basePath, atomically: true, encoding: .utf8)

        let overridePath = tempDir.appendingPathComponent("override.yml")
        try """
        services:
          web:
            deploy:
              resources:
                limits:
                  memory: 1G
                reservations:
                  devices:
                    - driver: apple
                      capabilities: [gpu]
        """.write(to: overridePath, atomically: true, encoding: .utf8)

        let merged = try ComposeParser.parse(fileURLs: [basePath, overridePath])
        let limits = merged.services["web"]?.deploy?.resources?.limits
        let reservations = merged.services["web"]?.deploy?.resources?.reservations?.devices
        expect(limits?.cpus == "2", "merge retains base cpus")
        expect(limits?.memory == "1G", "merge applies override memory")
        expect(reservations?.count == 1, "merge applies gpu reservation device")
        expect(reservations?.first?.driver == "apple", "merge keeps gpu reservation driver")
    }

    private mutating func runGPUReservationMergePreserveBaseTests() throws {
        let tempDir = try Self.makeGPUReservationMergeDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let gpuBasePath = tempDir.appendingPathComponent("gpu-base.yml")
        try """
        services:
          web:
            image: docker.io/library/alpine:3.24
            command: sleep 300
            deploy:
              resources:
                reservations:
                  devices:
                    - driver: apple
                      capabilities: [gpu]
        """.write(to: gpuBasePath, atomically: true, encoding: .utf8)

        let limitsOnlyOverridePath = tempDir.appendingPathComponent("limits-only-override.yml")
        try """
        services:
          web:
            deploy:
              resources:
                limits:
                  memory: 1G
        """.write(to: limitsOnlyOverridePath, atomically: true, encoding: .utf8)

        let baseRetained = try ComposeParser.parse(fileURLs: [gpuBasePath, limitsOnlyOverridePath])
        let baseReservations = baseRetained.services["web"]?.deploy?.resources?.reservations?.devices
        expect(baseReservations?.count == 1, "merge retains base gpu reservation when override omits reservations")
        expect(baseReservations?.first?.driver == "apple", "merge retains base gpu reservation driver")
    }

    private mutating func runGPUReservationMergeClearBaseTests() throws {
        let tempDir = try Self.makeGPUReservationMergeDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let gpuBasePath = tempDir.appendingPathComponent("gpu-base.yml")
        try """
        services:
          web:
            image: docker.io/library/alpine:3.24
            command: sleep 300
            deploy:
              resources:
                reservations:
                  devices:
                    - driver: apple
                      capabilities: [gpu]
        """.write(to: gpuBasePath, atomically: true, encoding: .utf8)

        let emptyDevicesOverridePath = tempDir.appendingPathComponent("empty-devices-override.yml")
        try """
        services:
          web:
            deploy:
              resources:
                reservations:
                  devices: []
        """.write(to: emptyDevicesOverridePath, atomically: true, encoding: .utf8)

        let cleared = try ComposeParser.parse(fileURLs: [gpuBasePath, emptyDevicesOverridePath])
        let clearedDevices = cleared.services["web"]?.deploy?.resources?.reservations?.devices
        expect(clearedDevices?.isEmpty == true, "merge override with empty devices clears base gpu reservation")
    }

    private static func makeGPUReservationMergeDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("compose-verify-gpu-merge-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    private mutating func runGPUReservationDryRunTests() throws {
        let composeDirectory = Self.fixtureURL("resources-gpu-reservation-compose.yml").deletingLastPathComponent()
        let gpuFixture = try ComposeParser.parse(
            fileURL: Self.fixtureURL("resources-gpu-reservation-compose.yml")
        )
        expectComposeError(
            "dry-run up rejects unsupported gpu reservation during planning",
            matching: {
                if case .invalidField("deploy.resources.reservations.devices", let reason) = $0 {
                    return Self.matchesUnsupportedGPUReason(reason)
                }
                return false
            },
            body: {
                _ = try ServicePlanner.startupLayers(
                    for: gpuFixture,
                    projectName: "demo",
                    composeDirectory: composeDirectory,
                    activeProfiles: [],
                    scaleOverrides: [:]
                )
            }
        )
    }

    private mutating func expectGPUReservationPlanError(
        _ label: String,
        fixtureName: String,
        machineName: String?,
        matching: (ComposeError) -> Bool
    ) throws {
        let composeDirectory = Self.fixtureURL("resources-limits-compose.yml").deletingLastPathComponent()
        expectComposeError(label, matching: matching) {
            let composeFile = try ComposeParser.parse(fileURL: Self.fixtureURL(fixtureName))
            _ = try ServicePlanner.buildUpPlan(
                context: ServicePlanner.PlanningContext(
                    composeFile: composeFile,
                    projectName: "demo",
                    composeDirectory: composeDirectory,
                    machineName: machineName
                ),
                serviceName: "web",
                service: composeFile.services["web"]!,
                replicaIndex: 1
            )
        }
    }
}
