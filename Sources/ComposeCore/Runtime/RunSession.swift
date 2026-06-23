import ArgumentParser
import ContainerCommands
import Foundation

/// Foreground one-off container via upstream `ContainerRun` (no `-d`); interrupt stops run container only.
package enum RunSession {
    package static func run(
        plan: ServicePlan,
        shutdownContext: RunShutdownContext,
        useInteractivePTY: Bool = false,
        imagePullOutput: ImagePullOutput? = nil,
        runContainer: @escaping @Sendable (ServicePlan) async throws -> Int32 = { plan in
            try await defaultRunContainer(plan: plan)
        },
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
                if let imagePullOutput {
                    try await ImagePullRunner.pullMissing(plans: [plan], output: imagePullOutput)
                }
                if let imagePullOutput {
                    return try await defaultRunContainer(plan: plan, imagePullOutput: imagePullOutput)
                }
                return try await runContainer(plan)
            }
        )
    }

    package static func defaultRunContainer(
        plan: ServicePlan,
        imagePullOutput: ImagePullOutput? = nil
    ) async throws -> Int32 {
        // Remove a stale same-name container before start. Interrupt cleanup is owned by
        // `stopRunContainer` (graceful `--timeout`), not `teardownRespectingCancellation`.
        try await ContainerTeardown.teardown(id: plan.name)
        let runArguments = try ComposeFileStaging.preparedRunArguments(
            for: plan,
            imagePullOutput: imagePullOutput
        )
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
