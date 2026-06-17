import Foundation

package enum ComposeCommandClockSync {
    package static func apply(cliNoClockSync: Bool) {
        ClockSyncConfiguration.apply(cliNoClockSync: cliNoClockSync)
    }

    package static func execute<R>(
        cliNoClockSync: Bool,
        dryRun: Bool = false,
        eagerSync: Bool = true,
        _ body: () async throws -> R
    ) async throws -> R {
        apply(cliNoClockSync: cliNoClockSync)
        guard ClockSyncConfiguration.sessionEnabled, !dryRun else {
            return try await body()
        }
        await ClockSyncCoordinator.shared.beginSession()
        if eagerSync {
            await ClockSyncCoordinator.shared.syncIfNeeded(reason: .commandEntry)
        }
        do {
            let result = try await body()
            await ClockSyncCoordinator.shared.endSession()
            return result
        } catch {
            await ClockSyncCoordinator.shared.endSession()
            throw error
        }
    }
}
