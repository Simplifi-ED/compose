// container 1.0.0 exposes no per-container health on ContainerSnapshot; compose probes
// health by running the parsed healthcheck test via ContainerClient.createProcess.
import ContainerAPIClient
import ContainerResource
import Foundation

public struct HealthWaitContext: Sendable {
    public let services: [String: ComposeService]
    public let projectName: String
    public let scaleOverrides: [String: Int]

    public init(
        services: [String: ComposeService],
        projectName: String,
        scaleOverrides: [String: Int] = [:]
    ) {
        self.services = services
        self.projectName = projectName
        self.scaleOverrides = scaleOverrides
    }
}

public struct HealthGate: Sendable, Equatable {
    public let dependencyService: String
    public let condition: DependsOnCondition
    public let containerNames: [String]

    public init(
        dependencyService: String,
        condition: DependsOnCondition,
        containerNames: [String]
    ) {
        self.dependencyService = dependencyService
        self.condition = condition
        self.containerNames = containerNames
    }
}

package enum HealthWait {
    package typealias StatusProvider = @Sendable (String) async throws -> RuntimeStatus?
    package typealias ProcessRunner = @Sendable (String, ProcessConfiguration) async throws -> Int32

    private static let defaultStartedTimeout: Duration = .seconds(60)
    private static let statusPollInterval: Duration = .milliseconds(250)

    package static func gatesForNextLayer(
        nextLayer: [ServicePlan],
        context: HealthWaitContext
    ) throws -> [HealthGate] {
        struct GateKey: Hashable {
            let service: String
            let condition: DependsOnCondition
        }

        var merged: [GateKey: Set<String>] = [:]

        for plan in nextLayer {
            guard let service = context.services[plan.serviceName] else { continue }
            for dependency in service.dependsOn where dependency.requiresReadinessWait {
                guard let dependencyService = context.services[dependency.service] else { continue }
                let replicaCount = try ReplicaPlanning.resolvedReplicaCount(
                    serviceName: dependency.service,
                    service: dependencyService,
                    scaleOverrides: context.scaleOverrides
                )
                let containerNames = (1...replicaCount).map { index in
                    ReplicaPlanning.indexedContainerName(
                        projectName: context.projectName,
                        serviceName: dependency.service,
                        index: index
                    )
                }
                let key = GateKey(service: dependency.service, condition: dependency.condition)
                merged[key, default: []].formUnion(containerNames)
            }
        }

        return merged.map { key, containerNames in
            HealthGate(
                dependencyService: key.service,
                condition: key.condition,
                containerNames: containerNames.sorted()
            )
        }.sorted {
            $0.dependencyService == $1.dependencyService
                ? $0.condition.rawValue < $1.condition.rawValue
                : $0.dependencyService < $1.dependencyService
        }
    }

    package static func waitForDependencies(
        gates: [HealthGate],
        context: HealthWaitContext,
        status: @escaping StatusProvider = HealthProbe.defaultStatus,
        runProcess: @escaping ProcessRunner = HealthProbe.defaultProcessRunner
    ) async throws {
        guard !gates.isEmpty else { return }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for gate in gates {
                group.addTask {
                    try await waitForGate(
                        gate,
                        context: context,
                        status: status,
                        runProcess: runProcess
                    )
                }
            }
            try await group.waitForAll()
        }
    }

    private static func waitForGate(
        _ gate: HealthGate,
        context: HealthWaitContext,
        status: @escaping StatusProvider,
        runProcess: @escaping ProcessRunner
    ) async throws {
        for containerName in gate.containerNames {
            switch gate.condition {
            case .serviceStarted:
                try await waitForStarted(
                    containerName: containerName,
                    dependencyService: gate.dependencyService,
                    context: context,
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
                    context: context,
                    status: status,
                    runProcess: runProcess
                )
            case .orderingOnly:
                continue
            }
        }
    }

    private static func waitForStarted(
        containerName: String,
        dependencyService: String,
        context: HealthWaitContext,
        status: @escaping StatusProvider
    ) async throws {
        let timeout = defaultStartedTimeout
        let deadline = ContinuousClock.now + timeout

        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            if try await isRunning(containerName: containerName, status: status) {
                return
            }
            try await Task.sleep(for: statusPollInterval)
        }

        throw ComposeError.serviceStartTimeout(dependency: dependencyService, container: containerName)
    }

    private static func waitForHealthy(
        containerName: String,
        dependencyService: String,
        healthcheck: ComposeHealthcheck,
        context: HealthWaitContext,
        status: @escaping StatusProvider,
        runProcess: @escaping ProcessRunner
    ) async throws {
        try await waitForStarted(
            containerName: containerName,
            dependencyService: dependencyService,
            context: context,
            status: status
        )

        if healthcheck.startPeriod > .zero {
            try await Task.sleep(for: healthcheck.startPeriod)
        }

        var attempts = 0
        while attempts <= healthcheck.retries {
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

            attempts += 1
            if attempts > healthcheck.retries {
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
            return try await HealthProbe.withTimeout(healthcheck.timeout) {
                try await runProcess(containerName, config)
            }
        } catch is CancellationError {
            throw CancellationError()
        }
    }

}
