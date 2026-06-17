import ComposeCore
import Foundation

extension TestRunner {
    private static let resourceLimitsImage = "docker.io/library/alpine:3.24"

    mutating func runResourceLimitsValidationTests() throws {
        try runResourceLimitsErrorTests()
        try runResourceLimitsEdgeCaseTests()
        try runResourceLimitsConfigValidationTests()
    }

    private mutating func runResourceLimitsErrorTests() throws {
        try expectUpPlanError(
            "invalid memory limit at plan time",
            fixtureName: "resources-bad-memory-compose.yml"
        ) {
            if case .invalidField("deploy.resources.limits.memory", let reason) = $0 {
                return reason.contains("invalid size 'not-a-size'")
            }
            return false
        }
        try expectUpPlanError(
            "fractional cpu rejected at plan time",
            fixtureName: "resources-fractional-cpu-compose.yml"
        ) {
            if case .invalidField("deploy.resources.limits.cpus", let reason) = $0 {
                return reason == DeployResourceLimitsPlanning.fractionalCPUReason
            }
            return false
        }
        try expectUpPlanError(
            "millicore cpu rejected at plan time",
            fixtureName: "resources-millicore-cpu-compose.yml"
        ) {
            if case .invalidField("deploy.resources.limits.cpus", let reason) = $0 {
                return reason == DeployResourceLimitsPlanning.fractionalCPUReason
            }
            return false
        }
    }

    private mutating func runResourceLimitsEdgeCaseTests() throws {
        let composeDirectory = Self.fixtureURL("resources-limits-compose.yml").deletingLastPathComponent()
        let wholeFromDecimal = ComposeService(
            image: Self.resourceLimitsImage,
            command: .string("sleep 300"),
            ports: [],
            environment: .map([:]),
            containerName: nil,
            deploy: ComposeDeploy(
                replicas: nil,
                resources: ComposeDeployResources(
                    limits: ComposeResourceLimits(cpus: "2.0", memory: nil)
                )
            )
        )
        let decimalPlan = try ServicePlanner.buildUpPlan(
            context: ServicePlanner.PlanningContext(
                composeFile: ComposeFile(name: nil, services: ["web": wholeFromDecimal]),
                projectName: "demo",
                composeDirectory: composeDirectory
            ),
            serviceName: "web",
            service: wholeFromDecimal,
            replicaIndex: 1
        )
        expect(runArgumentValue(decimalPlan.runArguments, flag: "--cpus") == "2", "2.0 normalizes to whole cpu 2")

        try expectUpPlanError(
            "zero cpu rejected at plan time",
            fixtureName: "resources-zero-cpu-compose.yml"
        ) {
            if case .invalidField("deploy.resources.limits.cpus", let reason) = $0 {
                return reason.contains("expected a positive whole number")
            }
            return false
        }
        try expectUpPlanError(
            "empty cpu rejected at plan time",
            fixtureName: "resources-empty-cpu-compose.yml"
        ) {
            if case .invalidField("deploy.resources.limits.cpus", let reason) = $0 {
                return reason.contains("expected a positive whole number")
            }
            return false
        }
    }

    private mutating func runResourceLimitsConfigValidationTests() throws {
        try runResourceLimitsConfigRejectTests()
        try runResourceLimitsConfigQuietTests()
    }

    private mutating func runResourceLimitsConfigRejectTests() throws {
        let fractionalURL = Self.fixtureURL("resources-fractional-cpu-compose.yml")
        expectComposeError(
            "config rejects fractional cpu limit",
            matching: {
                if case .invalidField("deploy.resources.limits.cpus", let reason) = $0 {
                    return reason == DeployResourceLimitsPlanning.fractionalCPUReason
                }
                return false
            },
            body: {
                _ = try ComposeConfigResolver.resolve(
                    fileURLs: [fractionalURL],
                    activeProfiles: [],
                    scaleOverrides: [:]
                )
            }
        )

        let badMemoryURL = Self.fixtureURL("resources-bad-memory-compose.yml")
        expectComposeError(
            "config rejects invalid memory limit",
            matching: {
                if case .invalidField("deploy.resources.limits.memory", let reason) = $0 {
                    return reason.contains("invalid size 'not-a-size'")
                }
                return false
            },
            body: {
                _ = try ComposeConfigResolver.resolve(
                    fileURLs: [badMemoryURL],
                    activeProfiles: [],
                    scaleOverrides: [:]
                )
            }
        )
    }

    private mutating func runResourceLimitsConfigQuietTests() throws {
        let fractionalURL = Self.fixtureURL("resources-fractional-cpu-compose.yml")
        expectComposeError(
            "config quiet rejects invalid limits",
            matching: {
                if case .invalidField("deploy.resources.limits.cpus", _) = $0 { return true }
                return false
            },
            body: {
                _ = try ComposeConfigResolver.resolveOutput(
                    fileURLs: [fractionalURL],
                    activeProfiles: [],
                    scaleOverrides: [:],
                    quiet: true
                )
            }
        )

        let validURL = Self.fixtureURL("resources-limits-compose.yml")
        let quietOutput = try ComposeConfigResolver.resolveOutput(
            fileURLs: [validURL],
            activeProfiles: [],
            scaleOverrides: [:],
            quiet: true
        )
        expect(quietOutput == nil, "config quiet skips yaml for valid limits")
    }

}
