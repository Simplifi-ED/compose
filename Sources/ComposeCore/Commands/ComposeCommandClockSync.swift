import Foundation

package enum ComposeCommandClockSync {
    package static func execute<R>(
        cliNoClockSync: Bool,
        dryRun: Bool = false,
        eagerSync: Bool = true,
        cliNoOslog: Bool = false,
        _ body: () async throws -> R
    ) async throws -> R {
        ClockSyncConfiguration.apply(cliNoClockSync: cliNoClockSync)
        OsLogConfiguration.apply(cliNoOslog: cliNoOslog, dryRun: dryRun)
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
