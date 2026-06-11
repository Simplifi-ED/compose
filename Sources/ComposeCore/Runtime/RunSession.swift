import ArgumentParser
import ContainerCommands
import Foundation

/// Foreground one-off container via upstream `ContainerRun` (no `-d`); interrupt stops run container only.
package enum RunSession {
    package static func run(
        plan: ServicePlan,
        shutdownContext: RunShutdownContext,
        useInteractivePTY: Bool = false,
        runContainer: @escaping @Sendable (ServicePlan) async throws -> Int32 = defaultRunContainer,
        stopRunContainer: @escaping @Sendable (RunShutdownContext) async throws -> Void = {
            try await RunShutdownContext.stopAndRemove(context: $0)
        }
    ) async throws {
        let stdinRestore = InteractiveSession.StdinRestoreHandle(useInteractivePTY: useInteractivePTY)
        try await InteractiveSession.runUntilExit(
            policy: .stopRunContainer(shutdownContext),
            terminalCleanup: {
                stdinRestore.restore()
            },
            stopRunContainer: stopRunContainer,
            body: {
                try await runContainer(plan)
            }
        )
    }

    package static func defaultRunContainer(plan: ServicePlan) async throws -> Int32 {
        // Remove a stale same-name container before start. Interrupt cleanup is owned by
        // `stopRunContainer` (graceful `--timeout`), not `teardownRespectingCancellation`.
        try await ContainerTeardown.teardown(id: plan.name)
        let runArguments = try ComposeFileStaging.preparedRunArguments(for: plan)
        let command: Application.ContainerRun
        do {
            command = try Application.ContainerRun.parse(runArguments)
        } catch {
            ComposeFileStaging.removeContainerStaging(
                projectName: plan.projectName,
                containerName: plan.name
            )
            throw error
        }
        do {
            try await command.run()
            removeStagingAfterRunIfNeeded(for: plan)
            return 0
        } catch let exit as ExitCode {
            removeStagingAfterRunIfNeeded(for: plan)
            return exit.rawValue
        }
    }

    package static func removeStagingAfterRunIfNeeded(for plan: ServicePlan) {
        guard plan.removeContainerAfterExit else { return }
        ComposeFileStaging.removeContainerStaging(
            projectName: plan.projectName,
            containerName: plan.name
        )
    }
}
