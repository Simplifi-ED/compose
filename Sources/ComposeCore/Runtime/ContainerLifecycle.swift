import ContainerResource
import Foundation

/// Profile and project context for pause/unpause scoping.
package struct ProjectPauseScope: Sendable {
    package let context: ProjectOptions.LabelCommandContext
    package let profileFilterRequested: Bool
    package let activeProfiles: Set<String>
    package let tearsDownAll: Bool

    package init(
        context: ProjectOptions.LabelCommandContext,
        profileFilterRequested: Bool,
        activeProfiles: Set<String>,
        tearsDownAll: Bool
    ) {
        self.context = context
        self.profileFilterRequested = profileFilterRequested
        self.activeProfiles = activeProfiles
        self.tearsDownAll = tearsDownAll
    }
}

/// Suspend/resume orchestration for project containers (non-destructive freeze).
public enum ContainerLifecycle {
    public enum Operation: Sendable {
        case pause
        case unpause
    }

    package static func targetsForPause(from containers: [ProjectContainer]) -> [ProjectContainer] {
        containers.filter { $0.status == .running }
    }

    package static func targetsForUnpause(from containers: [ProjectContainer]) -> [ProjectContainer] {
        // RuntimeStatus.paused arrives with upstream container pause support (PR-2).
        pausedContainers(from: containers)
    }

    package static func filteredTargetNames(
        discovered: [DiscoveredContainer],
        projectContainers: [ProjectContainer],
        scope: ProjectPauseScope,
        operation: Operation
    ) throws -> [String] {
        let filtered: [DiscoveredContainer]
        if scope.profileFilterRequested {
            let serviceFilter = try ProfileFilter.downServiceFilter(
                composeFile: scope.context.composeFile,
                activeProfiles: scope.activeProfiles,
                tearsDownAll: scope.tearsDownAll
            )
            filtered = ProjectStatus.filteredDiscoveredContainers(from: discovered, filter: serviceFilter)
        } else {
            filtered = discovered
        }
        let names = Set(filtered.map(\.name))
        let scoped = projectContainers.filter { names.contains($0.name) }
        let targets =
            switch operation {
            case .pause: targetsForPause(from: scoped)
            case .unpause: targetsForUnpause(from: scoped)
            }
        return targets.map(\.name).sorted()
    }

    package static func apply(
        names: [String],
        operation: Operation,
        execution: WaveExecutionPolicy,
        machineContext: MachineContext,
        dryRunManifest: DryRunManifest?
    ) async throws -> [String] {
        guard !names.isEmpty else { return [] }

        if let dryRunManifest {
            for name in names {
                switch operation {
                case .pause:
                    await dryRunManifest.recordPause(name)
                case .unpause:
                    await dryRunManifest.recordUnpause(name)
                }
            }
            return names
        }

        let result = await ServiceRunner.parallelRun(
            names.map { ServiceRunner.ParallelRunItem(label: $0, collectOnSuccess: $0, value: $0) },
            maxConcurrent: execution.maxConcurrent
        ) { name in
            switch operation {
            case .pause:
                try await ComposeContainerGateway.pause(id: name, machineContext: machineContext)
            case .unpause:
                try await ComposeContainerGateway.unpause(id: name, machineContext: machineContext)
            }
        }

        if result.wasInterrupted {
            throw CancellationError()
        }
        if !result.failures.isEmpty {
            throw ComposeError.multipleServiceFailures(result.failures)
        }
        return result.succeeded.sorted()
    }

    private static func pausedContainers(from containers: [ProjectContainer]) -> [ProjectContainer] {
        guard let pausedStatus = RuntimeStatus.pausedIfAvailable else { return [] }
        return containers.filter { $0.status == pausedStatus }
    }
}

private extension RuntimeStatus {
    /// Returns `.paused` when upstream container adds the case; nil until then.
    static var pausedIfAvailable: RuntimeStatus? {
        nil
    }
}
