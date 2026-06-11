import Foundation

public enum OrphanRemoval {
    public enum Policy: Sendable {
        /// `up --remove-orphans`: yaml drift, unlabeled, and profile-inactive containers.
        case beforeUp(activeProfiles: Set<String>)
        /// `down --remove-orphans`: profile-skipped orphans only when `--profile` narrows teardown.
        case duringDown(
            profileFilterRequested: Bool,
            tearsDownAll: Bool,
            activeProfiles: Set<String>
        )
        /// Ordered shutdown final wave: yaml drift and unlabeled only.
        case yamlOnly
    }

    public static func orphans(
        in containers: [DiscoveredContainer],
        composeFile: ComposeFile,
        policy: Policy
    ) -> [DiscoveredContainer] {
        let (activeProfiles, includeProfileSkipped) = policyParameters(policy)
        let knownServices = Set(composeFile.services.keys)
        let activeServiceNames = ProfileFilter.matchingServiceNames(
            from: composeFile.services,
            activeProfiles: activeProfiles,
            includeAll: false
        )

        return containers.filter { container in
            guard let serviceName = container.serviceName else { return true }
            if !knownServices.contains(serviceName) {
                return true
            }
            if includeProfileSkipped, !activeServiceNames.contains(serviceName) {
                return true
            }
            return false
        }
        .sorted { $0.name < $1.name }
    }

    public static func mergingContainers(
        _ target: [DiscoveredContainer],
        with orphans: [DiscoveredContainer]
    ) -> [DiscoveredContainer] {
        var byName = Dictionary(uniqueKeysWithValues: target.map { ($0.name, $0) })
        for orphan in orphans {
            byName[orphan.name] = orphan
        }
        return byName.values.sorted { $0.name < $1.name }
    }

    public static func removeOrphans(
        _ orphans: [DiscoveredContainer],
        onRemoved: (@Sendable (String) -> Void)? = nil
    ) async throws {
        guard !orphans.isEmpty else { return }

        let result = await ServiceRunner.parallelRun(
            orphans.map {
                ServiceRunner.ParallelRunItem(label: $0.name, collectOnSuccess: $0.name, value: $0)
            }
        ) { container in
            try await ContainerTeardown.teardownRespectingCancellation(id: container.name)
        }

        if !result.succeeded.isEmpty {
            WorkspaceHygieneOutput.printOrphanRemovalSummary(
                count: result.succeeded.count,
                names: result.succeeded.sorted()
            )
        }

        if result.wasInterrupted {
            throw CancellationError()
        }
        if !result.failures.isEmpty {
            throw ComposeError.multipleServiceFailures(result.failures)
        }

        for name in result.succeeded.sorted() {
            onRemoved?(name)
        }
    }

    private static func policyParameters(
        _ policy: Policy
    ) -> (activeProfiles: Set<String>, includeProfileSkipped: Bool) {
        switch policy {
        case .beforeUp(let activeProfiles):
            return (activeProfiles, true)
        case .duringDown(let profileFilterRequested, let tearsDownAll, let activeProfiles):
            return (activeProfiles, profileFilterRequested && !tearsDownAll)
        case .yamlOnly:
            return ([], false)
        }
    }
}
