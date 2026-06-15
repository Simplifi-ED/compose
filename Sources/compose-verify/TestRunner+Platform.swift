import ComposeCore
import ContainerCommands
import Foundation

extension TestRunner {
    private static let platformImage = "docker.io/library/alpine:3.24"

    mutating func runPlatformTests() throws {
        try runPlatformDecodeTests()
        try runPlatformConfigTests()
        try runPlatformRunMappingTests()
        try runPlatformValidationTests()
        try runPlatformDryRunTests()
    }

    private mutating func runPlatformDecodeTests() throws {
        let amd64 = try ComposeParser.parse(fileURL: Self.fixtureURL("platform-amd64-compose.yml"))
        expect(amd64.services["web"]?.platform == "linux/amd64", "platform amd64 decode")

        let x86 = try ComposeParser.parse(fileURL: Self.fixtureURL("platform-x86-compose.yml"))
        expect(x86.services["web"]?.platform == "linux/x86_64", "platform x86_64 decode")

        let arm64 = try ComposeParser.parse(fileURL: Self.fixtureURL("platform-arm64-compose.yml"))
        expect(arm64.services["web"]?.platform == "linux/arm64", "platform arm64 decode")
    }

    private mutating func runPlatformConfigTests() throws {
        let fileURL = Self.fixtureURL("platform-x86-compose.yml")
        let resolved = try ComposeConfigResolver.resolve(
            fileURLs: [fileURL],
            activeProfiles: [],
            scaleOverrides: [:]
        )
        let yaml = try ComposeSerializer.yamlString(from: resolved)
        expect(yaml.contains("platform: linux/amd64"), "config yaml normalizes x86_64 to amd64")
    }

    private mutating func runPlatformRunMappingTests() throws {
        try runPlatformAmd64UpMappingTests()
        try runPlatformAmd64RunMappingTests()
        try runPlatformNativeOmitTests()
    }

    private mutating func runPlatformAmd64UpMappingTests() throws {
        let fixturesDirectory = Self.fixtureURL("platform-amd64-compose.yml").deletingLastPathComponent()
        let composeFile = try ComposeParser.parse(fileURL: Self.fixtureURL("platform-amd64-compose.yml"))
        let context = ServicePlanner.PlanningContext(
            composeFile: composeFile,
            projectName: "demo",
            composeDirectory: fixturesDirectory
        )

        let upPlan = try ServicePlanner.buildUpPlan(
            context: context,
            serviceName: "web",
            service: composeFile.services["web"]!,
            replicaIndex: 1
        )
        expect(upPlan.runArguments.contains("--platform"), "up plan includes --platform")
        expect(upPlan.runArguments.contains("linux/amd64"), "up plan uses linux/amd64")
        let platformIndex = upPlan.runArguments.firstIndex(of: "--platform")
        let imageIndex = upPlan.runArguments.firstIndex(of: Self.platformImage)
        if let platformIndex, let imageIndex {
            expect(platformIndex < imageIndex, "platform flag precedes image ref")
        } else {
            expect(false, "up plan missing platform flag or image")
        }
        _ = try Application.ContainerRun.parse(upPlan.runArguments)
    }

    private mutating func runPlatformAmd64RunMappingTests() throws {
        guard RosettaAvailability.isInstalled() else { return }
        let fixturesDirectory = Self.fixtureURL("platform-amd64-compose.yml").deletingLastPathComponent()
        let composeFile = try ComposeParser.parse(fileURL: Self.fixtureURL("platform-amd64-compose.yml"))
        let context = ServicePlanner.PlanningContext(
            composeFile: composeFile,
            projectName: "demo",
            composeDirectory: fixturesDirectory
        )
        let runPlan = try ServicePlanner.runPlan(
            context: context,
            serviceName: "web",
            service: composeFile.services["web"]!,
            options: RunPlanOptions(
                removeContainer: false,
                commandOverride: nil,
                interactive: false,
                processTerminal: false,
                nameSuffix: "00000001"
            )
        )
        expect(runPlan.runArguments.contains("--platform"), "run plan includes --platform")
        _ = try Application.ContainerRun.parse(runPlan.runArguments)
    }

    private mutating func runPlatformNativeOmitTests() throws {
        let fixturesDirectory = Self.fixtureURL("platform-arm64-compose.yml").deletingLastPathComponent()
        let arm64File = try ComposeParser.parse(fileURL: Self.fixtureURL("platform-arm64-compose.yml"))
        let context = ServicePlanner.PlanningContext(
            composeFile: arm64File,
            projectName: "demo",
            composeDirectory: fixturesDirectory
        )
        let nativePlan = try ServicePlanner.buildUpPlan(
            context: context,
            serviceName: "web",
            service: arm64File.services["web"]!,
            replicaIndex: 1
        )
        guard RosettaAvailability.hostMachine() == "arm64" else { return }
        expect(!nativePlan.runArguments.contains("--platform"), "native arm64 omits --platform on arm64 host")
    }

    private mutating func runPlatformValidationTests() throws {
        try runPlatformValidateInjectedTests()
        try runPlatformValidateIntegrationTests()
    }

    private mutating func runPlatformValidateInjectedTests() throws {
        try runPlatformValidateSuccessCase()
        try runPlatformValidateFailureCases()
    }

    private mutating func runPlatformValidateSuccessCase() throws {
        let composeFile = try ComposeParser.parse(fileURL: Self.fixtureURL("platform-amd64-compose.yml"))
        try PlatformPlanning.validate(
            services: composeFile.services,
            activeServiceNames: ["web"],
            machineName: nil,
            hostMachine: "arm64",
            rosettaInstalled: { true }
        )
    }

    private mutating func runPlatformValidateFailureCases() throws {
        let composeFile = try ComposeParser.parse(fileURL: Self.fixtureURL("platform-amd64-compose.yml"))

        expectComposeError("platform rejects missing rosetta") { error in
            if case .invalidField("services.web.platform", let reason) = error {
                return reason == PlatformPlanning.rosettaMissingReason
            }
            return false
        } body: {
            try PlatformPlanning.validate(
                services: composeFile.services,
                activeServiceNames: ["web"],
                machineName: nil,
                hostMachine: "arm64",
                rosettaInstalled: { false }
            )
        }

        expectComposeError("platform rejects non-arm64 host for amd64") { error in
            if case .invalidField("services.web.platform", let reason) = error {
                return reason == PlatformPlanning.amd64RequiresAppleSiliconReason
            }
            return false
        } body: {
            try PlatformPlanning.validate(
                services: composeFile.services,
                activeServiceNames: ["web"],
                machineName: nil,
                hostMachine: "x86_64",
                rosettaInstalled: { true }
            )
        }

        expectComposeError("platform rejects machine mode") { error in
            if case .invalidField("services.web.platform", let reason) = error {
                return reason == PlatformPlanning.machineUnsupportedReason
            }
            return false
        } body: {
            try PlatformPlanning.validate(
                services: composeFile.services,
                activeServiceNames: ["web"],
                machineName: "dev",
                hostMachine: "arm64",
                rosettaInstalled: { true }
            )
        }
    }

    private mutating func runPlatformValidateIntegrationTests() throws {
        let composeFile = try ComposeParser.parse(fileURL: Self.fixtureURL("platform-amd64-compose.yml"))
        let fixturesDirectory = Self.fixtureURL("platform-amd64-compose.yml").deletingLastPathComponent()
        let invalidFile = try ComposeParser.parse(fileURL: Self.fixtureURL("platform-invalid-compose.yml"))

        expectComposeError("invalid platform at plan time") { error in
            if case .invalidField("services.web.platform", _) = error { return true }
            return false
        } body: {
            _ = try ServicePlanner.startupLayers(
                for: invalidFile,
                projectName: "demo",
                composeDirectory: fixturesDirectory
            )
        }

        guard RosettaAvailability.isInstalled(), RosettaAvailability.hostMachine() == "arm64" else { return }
        _ = try ServicePlanner.startupLayers(
            for: composeFile,
            projectName: "demo",
            composeDirectory: fixturesDirectory,
            machineName: nil
        )
    }

    private mutating func runPlatformDryRunTests() throws {
        let fixturesDirectory = Self.fixtureURL("platform-amd64-compose.yml").deletingLastPathComponent()
        let composeFile = try ComposeParser.parse(fileURL: Self.fixtureURL("platform-amd64-compose.yml"))
        let context = ServicePlanner.PlanningContext(
            composeFile: composeFile,
            projectName: "demo",
            composeDirectory: fixturesDirectory
        )
        let plan = try ServicePlanner.buildUpPlan(
            context: context,
            serviceName: "web",
            service: composeFile.services["web"]!,
            replicaIndex: 1
        )
        let formatted = DryRunManifestFormatting.formatCreate(plan)
        expect(formatted.contains("platform=\"linux/amd64\""), "dry-run create shows platform")
    }
}
