import Foundation

public actor DryRunManifest {
    public enum TeardownReason: Sendable, Equatable {
        case shutdown
        case orphan
    }

    private struct Entry: Sendable {
        let group: Int
        let sortKey: String
        let line: String
    }

    private var entries: [Entry] = []
    private var groupOrder = 0
    private var currentGroup = 0
    private var orphanNames: Set<String> = []

    public init() {}

    public func setUpWaveIndex(_ index: Int) {
        groupOrder += 1
        currentGroup = groupOrder
    }

    public func setDownWaveIndex(_ index: Int) {
        groupOrder += 1
        currentGroup = groupOrder
    }

    public func recordBuild(
        service: String,
        tag: String,
        context: String,
        dockerfile: String?
    ) {
        append(
            group: 0,
            sortKey: "build:\(service)",
            line: DryRunManifestFormatting.formatBuild(
                service: service,
                tag: tag,
                context: context,
                dockerfile: dockerfile
            )
        )
    }

    public func recordCreate(_ plan: ServicePlan) {
        append(
            group: currentGroup,
            sortKey: plan.name,
            line: DryRunManifestFormatting.formatCreate(plan)
        )
    }

    public func recordTeardown(_ name: String, reason: TeardownReason) {
        let group: Int
        if reason == .orphan {
            group = 0
        } else {
            group = currentGroup
        }
        append(
            group: group,
            sortKey: name,
            line: DryRunManifestFormatting.formatTeardown(name, reason: reason)
        )
    }

    public func recordHealthWait(_ gate: HealthGate) {
        append(
            group: currentGroup,
            sortKey: "\(gate.dependencyService):\(gate.condition.rawValue)",
            line: DryRunManifestFormatting.formatHealthWait(gate)
        )
    }

    public func recordExec(container: String, command: [String]) {
        groupOrder += 1
        currentGroup = groupOrder
        append(
            group: currentGroup,
            sortKey: container,
            line: DryRunManifestFormatting.formatExec(container: container, command: command)
        )
    }

    package func recordCp(
        container: String,
        direction: CpSession.Direction,
        source: String,
        destination: String
    ) {
        groupOrder += 1
        currentGroup = groupOrder
        append(
            group: currentGroup,
            sortKey: container,
            line: DryRunManifestFormatting.formatCp(
                container: container,
                direction: direction,
                source: source,
                destination: destination
            )
        )
    }

    public func recordPurge(paths: [String]) {
        groupOrder += 1
        currentGroup = groupOrder
        for path in paths.sorted() {
            append(
                group: currentGroup,
                sortKey: path,
                line: DryRunManifestFormatting.formatPurge(path: path)
            )
        }
    }

    public func sortedLines() -> [String] {
        entries
            .sorted {
                if $0.group != $1.group { return $0.group < $1.group }
                return $0.sortKey < $1.sortKey
            }
            .map(\.line)
    }

    public func printLines() {
        for line in sortedLines() {
            print(line)
        }
    }

    package func makeUpHooks() -> ServiceRunner.UpOperationHooks {
        ServiceRunner.UpOperationHooks(
            runContainer: { plan in
                await self.recordCreate(plan)
            },
            rollbackTeardown: { _ in },
            waitForDependencies: { gates, _ in
                await self.beginHealthWaitGroup()
                for gate in gates {
                    await self.recordHealthWait(gate)
                }
            }
        )
    }

    public func setOrphanNames(_ names: Set<String>) {
        orphanNames = names
    }

    package func makeDownTeardown() -> @Sendable (DiscoveredContainer) async throws -> Void {
        let names = orphanNames
        return { container in
            let reason: TeardownReason = names.contains(container.name) ? .orphan : .shutdown
            await self.recordTeardown(container.name, reason: reason)
        }
    }

    private func beginHealthWaitGroup() {
        groupOrder += 1
        currentGroup = groupOrder
    }

    private func append(group: Int, sortKey: String, line: String) {
        entries.append(Entry(group: group, sortKey: sortKey, line: line))
    }
}
