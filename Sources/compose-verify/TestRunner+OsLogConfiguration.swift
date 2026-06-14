import ComposeCore
import Foundation

extension TestRunner {
    mutating func runOsLogConfigurationTests() {
        OsLogConfiguration.resetForTesting()
        runOsLogConfigurationResolveTests()
        runOsLogConfigurationApplyTests()
        expect(
            OsLogConfiguration.subsystem == "com.simplifi-ed.container-compose",
            "subsystem matches project identifier"
        )
        OsLogConfiguration.resetForTesting()
    }

    private mutating func runOsLogConfigurationResolveTests() {
        expect(
            OsLogConfiguration.resolve(environment: [:], cliDisabled: false, dryRun: false),
            "os log enabled by default"
        )
        expect(
            !OsLogConfiguration.resolve(
                environment: [OsLogConfiguration.environmentVariableName: "0"],
                cliDisabled: false,
                dryRun: false
            ),
            "COMPOSE_OSLOG=0 disables telemetry"
        )
        expect(
            !OsLogConfiguration.resolve(
                environment: [OsLogConfiguration.environmentVariableName: "false"],
                cliDisabled: false,
                dryRun: false
            ),
            "COMPOSE_OSLOG=false disables telemetry"
        )
        expect(
            !OsLogConfiguration.resolve(
                environment: [OsLogConfiguration.environmentVariableName: "no"],
                cliDisabled: false,
                dryRun: false
            ),
            "COMPOSE_OSLOG=no disables telemetry"
        )
        expect(
            !OsLogConfiguration.resolve(environment: [:], cliDisabled: true, dryRun: false),
            "--no-oslog disables telemetry"
        )
        expect(
            !OsLogConfiguration.resolve(environment: [:], cliDisabled: false, dryRun: true),
            "dry-run disables telemetry"
        )
        expect(
            !OsLogConfiguration.resolve(
                environment: [OsLogConfiguration.environmentVariableName: "1"],
                cliDisabled: true,
                dryRun: false
            ),
            "CLI disable wins over COMPOSE_OSLOG=1"
        )
    }

    private mutating func runOsLogConfigurationApplyTests() {
        OsLogConfiguration.apply(cliNoOslog: false, dryRun: false, environment: [:])
        expect(OsLogConfiguration.sessionEnabled, "apply enables session by default")
        OsLogConfiguration.apply(cliNoOslog: true, dryRun: false, environment: [:])
        expect(!OsLogConfiguration.sessionEnabled, "apply respects CLI disable")
        OsLogConfiguration.apply(cliNoOslog: false, dryRun: true, environment: [:])
        expect(!OsLogConfiguration.sessionEnabled, "apply respects dry-run")
    }
}
