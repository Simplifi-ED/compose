import ComposeCore
import ContainerResource
import Foundation

extension TestRunner {
    mutating func runClockSyncTests() {
        ClockSyncConfiguration.resetForTesting()
        blockingAwait { await ClockSyncCoordinator.shared.resetForTesting() }
        runClockSyncConfigurationTests()
        runClockSyncDiscoveryTests()
        runClockSyncCoordinatorTests()
        ClockSyncConfiguration.resetForTesting()
        blockingAwait { await ClockSyncCoordinator.shared.resetForTesting() }
    }

    private mutating func runClockSyncConfigurationTests() {
        expect(
            ClockSyncConfiguration.resolve(environment: [:], cliDisabled: false),
            "clock sync enabled by default"
        )
        expect(
            !ClockSyncConfiguration.resolve(
                environment: [ClockSyncConfiguration.environmentVariableName: "0"],
                cliDisabled: false
            ),
            "COMPOSE_CLOCK_SYNC=0 disables clock sync"
        )
        expect(
            !ClockSyncConfiguration.resolve(
                environment: [ClockSyncConfiguration.environmentVariableName: "false"],
                cliDisabled: false
            ),
            "COMPOSE_CLOCK_SYNC=false disables clock sync"
        )
        expect(
            !ClockSyncConfiguration.resolve(environment: [:], cliDisabled: true),
            "--no-clock-sync disables clock sync"
        )
        expect(
            !ClockSyncConfiguration.resolve(
                environment: [ClockSyncConfiguration.environmentVariableName: "1"],
                cliDisabled: true
            ),
            "CLI disable wins over COMPOSE_CLOCK_SYNC=1"
        )
        ClockSyncConfiguration.apply(cliNoClockSync: false, environment: [:])
        expect(ClockSyncConfiguration.sessionEnabled, "clock sync enabled after apply")
        ClockSyncConfiguration.apply(
            cliNoClockSync: true,
            environment: [ClockSyncConfiguration.environmentVariableName: "1"]
        )
        expect(!ClockSyncConfiguration.sessionEnabled, "apply honors CLI disable over env")
    }

    private mutating func runClockSyncDiscoveryTests() {
        let hostSnapshot = Self.makeContainerSnapshot(
            project: "demo",
            service: "web",
            status: .running
        )
        let machineLabeled = Self.makeContainerSnapshot(
            project: "demo",
            service: "api",
            status: .running,
            extraLabels: [ComposeLabels.machine: "dev"]
        )
        let stopped = Self.makeContainerSnapshot(
            project: "demo",
            service: "worker",
            status: .stopped
        )
        let hostIDs = ClockSyncDiscovery.hostContainerIDs(
            from: [hostSnapshot, machineLabeled, stopped]
        )
        expect(hostIDs == ["demo_web_1"], "host discovery excludes machine-labeled and stopped")

        let emptyHypervisors = ClockSyncDiscovery.machineHypervisorIDs(
            machines: [],
            inVMContainers: [:]
        )
        expect(emptyHypervisors.isEmpty, "machine hypervisor discovery empty without machines")
    }

    private mutating func runClockSyncCoordinatorTests() {
        blockingAwait {
            await ClockSyncCoordinator.shared.beginSession()
            await ClockSyncCoordinator.shared.beginSession()
            await ClockSyncCoordinator.shared.endSession()
            await ClockSyncCoordinator.shared.endSession()

            await ClockSyncCoordinator.shared.resetForTesting()
            ClockSyncConfiguration.apply(cliNoClockSync: false)
            let stream = AsyncStream<Void> { continuation in
                continuation.yield()
                continuation.finish()
            }
            await ClockSyncCoordinator.shared.setWakeEventsFactoryForTesting { stream }
            await ClockSyncCoordinator.shared.beginSession()
            await ClockSyncCoordinator.shared.endSession()
        }
        expect(true, "wake observer installs and tears down without crash")
    }
}
