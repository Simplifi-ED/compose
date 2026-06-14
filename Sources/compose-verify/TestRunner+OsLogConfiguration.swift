import ComposeCore
import Foundation

extension TestRunner {
    mutating func runOsLogConfigurationTests() {
        OsLogConfiguration.resetForTesting()
        runOsLogConfigurationResolveTests()
        runOsLogConfigurationApplyTests()
        runSignpostTelemetryGateTests()
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

    private mutating func runSignpostTelemetryGateTests() {
        OsLogConfiguration.sessionEnabled = false
        var disabledRuns = 0
        let disabledValue = SignpostTelemetry.interval(SignpostTelemetry.parse) {
            disabledRuns += 1
            return 42
        }
        expect(disabledRuns == 1, "sync signpost gate runs body when disabled")
        expect(disabledValue == 42, "sync signpost gate preserves result when disabled")

        OsLogConfiguration.sessionEnabled = true
        var enabledRuns = 0
        let enabledValue = SignpostTelemetry.interval(SignpostTelemetry.parse) {
            enabledRuns += 1
            return 42
        }
        expect(enabledRuns == 1, "sync signpost gate runs body when enabled")
        expect(enabledValue == 42, "sync signpost gate preserves result when enabled")

        runSignpostTelemetryAsyncGateTests()
    }

    private mutating func runSignpostTelemetryAsyncGateTests() {
        final class RunCounter: @unchecked Sendable {
            var count = 0
        }

        OsLogConfiguration.sessionEnabled = false
        let disabledCounter = RunCounter()
        let disabledOutcome = blockingAwait { () -> (Int, Int) in
            let value = await SignpostTelemetry.interval(SignpostTelemetry.discovery) {
                await Task.yield()
                disabledCounter.count += 1
                return [ProjectContainer(
                    name: "demo_web_1",
                    serviceName: "web",
                    status: .running,
                    publishedPorts: []
                )]
            }
            return (disabledCounter.count, value.count)
        }
        expect(disabledOutcome.0 == 1, "async signpost gate runs body when disabled")
        expect(disabledOutcome.1 == 1, "async signpost gate preserves result when disabled")

        OsLogConfiguration.sessionEnabled = true
        let enabledCounter = RunCounter()
        let enabledOutcome = blockingAwait { () -> (Int, Int) in
            let value = await SignpostTelemetry.interval(SignpostTelemetry.discovery) {
                await Task.yield()
                enabledCounter.count += 1
                return [ProjectContainer(
                    name: "demo_web_1",
                    serviceName: "web",
                    status: .running,
                    publishedPorts: []
                )]
            }
            return (enabledCounter.count, value.count)
        }
        expect(enabledOutcome.0 == 1, "async signpost gate runs body when enabled")
        expect(enabledOutcome.1 == 1, "async signpost gate preserves result when enabled")
    }
}
