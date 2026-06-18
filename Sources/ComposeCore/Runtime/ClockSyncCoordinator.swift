import Foundation

package actor ClockSyncCoordinator {
    package static let shared = ClockSyncCoordinator()

    private var sessionCount = 0
    private var observerTask: Task<Void, Never>?
    private var commandEntrySynced = false
    private var wakeDebounceTask: Task<Void, Never>?
    private var isSyncing = false
    private let debounceNanos: UInt64 = 2_000_000_000

    package var wakeEventsFactory: (@Sendable () -> AsyncStream<Void>)?

    package func beginSession() {
        sessionCount += 1
        guard sessionCount == 1 else { return }
        startWakeObserver()
    }

    package func endSession() {
        guard sessionCount > 0 else { return }
        sessionCount -= 1
        guard sessionCount == 0 else { return }
        stopWakeObserver()
        commandEntrySynced = false
    }

    package func syncIfNeeded(reason: ClockSync.Reason) async {
        guard ClockSyncConfiguration.sessionEnabled else { return }
        switch reason {
        case .commandEntry:
            guard !commandEntrySynced else { return }
            commandEntrySynced = true
        case .afterUp, .wake:
            break
        }
        await performSync(reason: reason)
    }

    private func performSync(reason: ClockSync.Reason) async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        _ = await ClockSync.syncComposeWorkloads(reason: reason)
    }

    package func setWakeEventsFactoryForTesting(
        _ factory: @escaping @Sendable () -> AsyncStream<Void>
    ) {
        wakeEventsFactory = factory
    }

    package func resetForTesting() {
        sessionCount = 0
        commandEntrySynced = false
        wakeEventsFactory = nil
        stopWakeObserver()
    }

    private func startWakeObserver() {
        #if os(macOS)
        stopWakeObserver()
        let stream: AsyncStream<Void> = {
            if let wakeEventsFactory {
                return wakeEventsFactory()
            }
            return HostWakeObserver.events()
        }()
        observerTask = Task {
            for await _ in stream {
                guard !Task.isCancelled else { return }
                scheduleWakeSync()
            }
        }
        #endif
    }

    private func stopWakeObserver() {
        observerTask?.cancel()
        observerTask = nil
        wakeDebounceTask?.cancel()
        wakeDebounceTask = nil
    }

    private func scheduleWakeSync() {
        wakeDebounceTask?.cancel()
        wakeDebounceTask = Task {
            do {
                try await Task.sleep(nanoseconds: debounceNanos)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await performSync(reason: .wake)
        }
    }
}
