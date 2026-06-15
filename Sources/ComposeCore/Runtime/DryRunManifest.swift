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
    private let machineName: String?

    public init(machineName: String? = nil) {
        self.machineName = machineName
    }

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

    public func recordNetworkCreate(name: String) {
        append(
            group: 0,
            sortKey: "network:\(name)",
            line: DryRunManifestFormatting.formatNetworkCreate(name: name)
        )
    }

    public func recordVolumeCreate(name: String) {
        append(
            group: 0,
            sortKey: "volume:\(name)",
            line: DryRunManifestFormatting.formatVolumeCreate(name: name)
        )
    }

    public func recordNetworkRemovals(names: [String]) {
        guard !names.isEmpty else { return }
        groupOrder += 1
        currentGroup = groupOrder
        for name in names.sorted() {
            append(
                group: currentGroup,
                sortKey: name,
                line: DryRunManifestFormatting.formatNetworkRemove(name: name)
            )
        }
    }

    public func recordHostDNSInstall(projectName: String, projectID: String, hostnames: [String]) {
        append(
            group: 0,
            sortKey: "host-dns:\(projectID)",
            line: DryRunManifestFormatting.formatHostDNSInstall(
                projectName: projectName,
                projectID: projectID,
                hostnames: hostnames
            )
        )
    }

    public func recordHostDNSRemove(projectName: String, projectID: String) {
        groupOrder += 1
        currentGroup = groupOrder
        append(
            group: currentGroup,
            sortKey: "host-dns:\(projectID)",
            line: DryRunManifestFormatting.formatHostDNSRemove(
                projectName: projectName,
                projectID: projectID
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

    public func recordPause(_ name: String) {
        append(
            group: currentGroup,
            sortKey: name,
            line: DryRunManifestFormatting.formatPause(name)
        )
    }

    public func recordUnpause(_ name: String) {
        append(
            group: currentGroup,
            sortKey: name,
            line: DryRunManifestFormatting.formatUnpause(name)
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

    public func recordVolumeRemovals(names: [String]) {
        guard !names.isEmpty else { return }
        beginGroupedSection()
        for name in names.sorted() {
            append(group: currentGroup, sortKey: name, line: DryRunManifestFormatting.formatVolumeRemove(name: name))
        }
    }

    package func beginGroupedSection() {
        groupOrder += 1
        currentGroup = groupOrder
    }

    package func appendTrimLine(sortKey: String, line: String) {
        append(group: currentGroup, sortKey: sortKey, line: line)
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

    package func makeUpHooks(
        machineContext: MachineContext = .applicationSandbox
    ) -> ServiceRunner.UpOperationHooks {
        _ = machineContext
        return ServiceRunner.UpOperationHooks(
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
        let prefixed: String
        if let machineName {
            prefixed = line.replacingOccurrences(
                of: "[DRY-RUN] ",
                with: "[DRY-RUN] machine=\(machineName) "
            )
        } else {
            prefixed = line
        }
        entries.append(Entry(group: group, sortKey: sortKey, line: prefixed))
    }
}
