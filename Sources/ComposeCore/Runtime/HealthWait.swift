// container 1.0.0 exposes no per-container health on ContainerSnapshot; compose probes
// health by running the parsed healthcheck test via ContainerClient.createProcess.
import ContainerAPIClient
import ContainerResource
import Foundation

package enum HealthWait {
    package typealias StatusProvider = @Sendable (String) async throws -> RuntimeStatus?
    package typealias ProcessRunner = @Sendable (String, ProcessConfiguration, Duration) async throws -> Int32
    package typealias ExitCodeProvider = InitExitWait.ExitCodeProvider

    private static let defaultStartedTimeout: Duration = .seconds(60)
    private static let statusPollInterval: Duration = .milliseconds(250)

    package static func gatesForNextLayer(
        nextLayer: [ServicePlan],
        context: HealthWaitContext
    ) throws -> [HealthGate] {
        try HealthGatePlanning.gatesForNextLayer(nextLayer: nextLayer, context: context)
    }

    package static func waitForDependencies(
        gates: [HealthGate],
        context: HealthWaitContext,
        machineContext: MachineContext = .applicationSandbox,
        status: StatusProvider? = nil,
        runProcess: ProcessRunner? = nil,
        waitForExit: ExitCodeProvider? = nil,
        completionGateTimeout: Duration? = nil
    ) async throws {
        let status = status ?? HealthProbe.statusProvider(machineContext: machineContext)
        let runProcess = runProcess ?? HealthProbe.processRunner(machineContext: machineContext)
        let waitForExit = waitForExit ?? InitExitWait.exitCodeProvider(machineContext: machineContext)
        let completionGateTimeout = completionGateTimeout ?? defaultStartedTimeout
        let options = DependencyWaitOptions(
            runProcess: runProcess,
            waitForExit: waitForExit,
            completionGateTimeout: completionGateTimeout
        )
        guard !gates.isEmpty else { return }

        let gatesByService = Dictionary(grouping: gates, by: \.dependencyService)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for serviceGates in gatesByService.values {
                group.addTask {
                    let ordered = serviceGates.sorted {
                        $0.condition.readinessSortOrder < $1.condition.readinessSortOrder
                    }
                    for gate in ordered {
                        try await waitForGate(
                            gate,
                            context: context,
                            status: status,
                            options: options
                        )
                    }
                }
            }
            try await group.waitForAll()
        }
    }

    private struct DependencyWaitOptions: Sendable {
        let runProcess: ProcessRunner
        let waitForExit: InitExitWait.ExitCodeProvider
        let completionGateTimeout: Duration
    }

    private static func waitForGate(
        _ gate: HealthGate,
        context: HealthWaitContext,
        status: @escaping StatusProvider,
        options: DependencyWaitOptions
    ) async throws {
        for containerName in gate.containerNames {
            switch gate.condition {
            case .serviceStarted:
                try await waitForStarted(
                    containerName: containerName,
                    dependencyService: gate.dependencyService,
                    status: status
                )
            case .serviceHealthy:
                guard let healthcheck = context.services[gate.dependencyService]?.healthcheck else {
                    throw ComposeError.invalidField(
                        "depends_on",
                        reason: "service '\(gate.dependencyService)' has no healthcheck."
                    )
                }
                try await waitForHealthy(
                    containerName: containerName,
                    dependencyService: gate.dependencyService,
                    healthcheck: healthcheck,
                    status: status,
                    runProcess: options.runProcess
                )
            case .serviceCompletedSuccessfully:
                try await waitForCompletedSuccessfully(
                    containerName: containerName,
                    dependencyService: gate.dependencyService,
                    status: status,
                    waitForExit: options.waitForExit,
                    completionGateTimeout: options.completionGateTimeout
                )
            case .orderingOnly:
                continue
            }
        }
    }

    private static func waitForStarted(
        containerName: String,
        dependencyService: String,
        status: @escaping StatusProvider
    ) async throws {
        let deadline = ContinuousClock.now + defaultStartedTimeout

        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            if try await isRunning(containerName: containerName, status: status) {
                return
            }
            try await Task.sleep(for: statusPollInterval)
        }

        throw ComposeError.serviceStartTimeout(dependency: dependencyService, container: containerName)
    }

    private static func waitForCompletedSuccessfully(
        containerName: String,
        dependencyService: String,
        status: @escaping StatusProvider,
        waitForExit: @escaping InitExitWait.ExitCodeProvider,
        completionGateTimeout: Duration
    ) async throws {
        let deadline = ContinuousClock.now + completionGateTimeout

        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            switch try await status(containerName) {
            case .running, .stopped:
                do {
                    let exitCode = try await waitForExit(containerName)
                    if exitCode == 0 {
                        return
                    }
                    throw ComposeError.serviceCompletedUnsuccessfully(
                        dependency: dependencyService,
                        container: containerName,
                        exitCode: exitCode
                    )
                } catch is InitExitWait.TimedOut {
                    throw ComposeError.serviceCompletionExitTimeout(
                        dependency: dependencyService,
                        container: containerName
                    )
                }
            case .stopping, .unknown, nil:
                break
            }
            try await Task.sleep(for: statusPollInterval)
        }

        throw ComposeError.serviceCompletionNeverAppeared(
            dependency: dependencyService,
            container: containerName
        )
    }

    private static func waitForHealthy(
        containerName: String,
        dependencyService: String,
        healthcheck: ComposeHealthcheck,
        status: @escaping StatusProvider,
        runProcess: @escaping ProcessRunner
    ) async throws {
        try await waitForStarted(
            containerName: containerName,
            dependencyService: dependencyService,
            status: status
        )

        let graceEnds = ContinuousClock.now + healthcheck.startPeriod
        var failures = 0

        while failures <= healthcheck.retries {
            try Task.checkCancellation()

            if try await !isRunning(containerName: containerName, status: status) {
                throw ComposeError.serviceStartTimeout(dependency: dependencyService, container: containerName)
            }

            let exitCode = try await runProbe(
                containerName: containerName,
                healthcheck: healthcheck,
                runProcess: runProcess
            )
            if exitCode == 0 {
                return
            }

            if ContinuousClock.now < graceEnds {
                try await Task.sleep(for: healthcheck.interval)
                continue
            }

            failures += 1
            if failures > healthcheck.retries {
                throw ComposeError.healthCheckTimeout(dependency: dependencyService, container: containerName)
            }
            try await Task.sleep(for: healthcheck.interval)
        }
    }

    private static func isRunning(
        containerName: String,
        status: @escaping StatusProvider
    ) async throws -> Bool {
        switch try await status(containerName) {
        case .running:
            return true
        case .stopped, .stopping, .unknown, nil:
            return false
        }
    }

    private static func runProbe(
        containerName: String,
        healthcheck: ComposeHealthcheck,
        runProcess: @escaping ProcessRunner
    ) async throws -> Int32 {
        let config = HealthProbe.processConfiguration(for: healthcheck.test)
        do {
            return try await runProcess(containerName, config, healthcheck.timeout)
        } catch is CancellationError {
            throw CancellationError()
        } catch is HealthProbe.TimedOut {
            return 1
        }
    }
}
