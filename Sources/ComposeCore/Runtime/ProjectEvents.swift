import ContainerAPIClient
import ContainerResource
import Foundation

/// Session-scoped host `ContainerClient` for foreground polling; released on ``end()``.
package struct ContainerListClientSession {
    private let machineContext: MachineContext
    private var hostClient: ContainerClient?
    package private(set) var isEnded = false

    package init(machineContext: MachineContext) {
        self.machineContext = machineContext
        if !machineContext.isMachineMode {
            hostClient = ContainerClient()
        }
    }

    package mutating func end() {
        hostClient = nil
        isEnded = true
    }

    package func projectContainers(forProject projectName: String) async throws -> [ProjectContainer] {
        guard !isEnded else { return [] }
        return try await ContainerDiscovery.projectContainers(
            forProject: projectName,
            machineContext: machineContext,
            hostClient: hostClient
        )
    }
}

package enum ProjectEventsDiff {
    package static func transitions(
        previous: [String: RuntimeStatus],
        current: [String: RuntimeStatus]
    ) -> [ProjectEventTransition] {
        var events: [ProjectEventTransition] = []
        let sortedCurrent = current.keys.sorted()

        for id in sortedCurrent {
            guard let status = current[id] else { continue }
            let prior = previous[id]
            if status == .running, prior != .running {
                events.append(ProjectEventTransition(kind: .start, containerID: id, containerName: id))
            } else if let prior, prior != .stopped, status == .stopped {
                events.append(ProjectEventTransition(kind: .die, containerID: id, containerName: id))
            }
        }

        for id in previous.keys.sorted() where current[id] == nil {
            events.append(ProjectEventTransition(kind: .die, containerID: id, containerName: id))
        }

        return events
    }

    package static func snapshotStarts(
        current: [String: RuntimeStatus]
    ) -> [ProjectEventTransition] {
        current.keys.sorted().compactMap { id in
            guard current[id] == .running else { return nil }
            return ProjectEventTransition(kind: .start, containerID: id, containerName: id)
        }
    }

    package static func statusMap(
        from containers: [ProjectContainer],
        serviceFilter: Set<String>?
    ) -> [String: RuntimeStatus] {
        let filtered = ProjectStatus.filteredContainers(from: containers, filter: serviceFilter)
        return Dictionary(uniqueKeysWithValues: filtered.map { ($0.name, $0.status) })
    }
}

package struct ProjectEventsOptions: Sendable {
    package let projectName: String
    package let serviceFilter: Set<String>?
    package let machineContext: MachineContext
    package let follow: Bool
    package let timeout: Duration?
    package let pollInterval: Duration

    package init(
        projectName: String,
        serviceFilter: Set<String>?,
        machineContext: MachineContext,
        follow: Bool,
        timeout: Duration? = nil,
        pollInterval: Duration = ProjectEventsSession.defaultPollInterval
    ) {
        self.projectName = projectName
        self.serviceFilter = serviceFilter
        self.machineContext = machineContext
        self.follow = follow
        self.timeout = timeout
        self.pollInterval = pollInterval
    }
}

package enum ProjectEventsSession {
    package static let defaultPollInterval: Duration = .milliseconds(1_500)

    package typealias ListProjectHandler = @Sendable (
        ProjectEventsOptions,
        inout ContainerListClientSession
    ) async throws -> [ProjectContainer]

    package typealias EmitHandler = @Sendable (ProjectEventTransition) -> Void

    package static func run(
        options: ProjectEventsOptions,
        listProject: @escaping ListProjectHandler = defaultListProject,
        emit: @escaping EmitHandler = defaultEmit
    ) async throws {
        TerminalOutput.prepareStdout()
        var session = ContainerListClientSession(machineContext: options.machineContext)
        defer { session.end() }
        try await runPolling(
            options: options,
            session: &session,
            listProject: listProject,
            emit: emit
        )
    }

    package static func runUntilCancelled(
        options: ProjectEventsOptions,
        policy: InterruptPolicy = .cancelOnly,
        onQuietCancel: (@Sendable () -> Void)? = nil,
        listProject: @escaping ListProjectHandler = defaultListProject,
        emit: @escaping EmitHandler = defaultEmit
    ) async throws -> SignalForwarding.ExitOutcome {
        TerminalOutput.prepareStdout()

        let outcome = try await SignalForwarding.runUntilCancelled(
            policy: policy,
            body: {
                try await run(
                    options: options,
                    listProject: listProject,
                    emit: emit
                )
            }
        )

        if outcome == .cancelledQuietly {
            onQuietCancel?()
        }
        return outcome
    }

    package static func runPolling(
        options: ProjectEventsOptions,
        session: inout ContainerListClientSession,
        listProject: @escaping ListProjectHandler = defaultListProject,
        emit: @escaping EmitHandler = defaultEmit
    ) async throws {
        var cache: [String: RuntimeStatus] = [:]
        let deadline = options.timeout.map { ContinuousClock.now.advanced(by: $0) }
        var sawContainers = false

        repeat {
            try Task.checkCancellation()

            let containers = try await listProject(options, &session)
            let current = ProjectEventsDiff.statusMap(from: containers, serviceFilter: options.serviceFilter)
            if !current.isEmpty {
                sawContainers = true
            }

            let transitions: [ProjectEventTransition]
            if options.follow {
                transitions = ProjectEventsDiff.transitions(previous: cache, current: current)
            } else {
                transitions = ProjectEventsDiff.snapshotStarts(current: current)
            }

            for transition in transitions {
                emit(transition)
            }

            cache = current

            if !options.follow {
                return
            }

            if let deadline, !sawContainers, ContinuousClock.now >= deadline {
                return
            }

            try await Task.sleep(for: options.pollInterval)
        } while options.follow
    }

    private static func defaultListProject(
        options: ProjectEventsOptions,
        session: inout ContainerListClientSession
    ) async throws -> [ProjectContainer] {
        try await session.projectContainers(forProject: options.projectName)
    }

    private static func defaultEmit(_ transition: ProjectEventTransition) {
        let line = ProjectEventFormat.formatLine(transition: transition, timestamp: Date())
        print(line, terminator: "")
        fflush(stdout)
    }
}
