import ArgumentParser
import Foundation

/// Post-start attach: multiplex logs and wait for started services to exit or user interrupt.
package enum AttachAfterUp {
    package static func run(
        plans: [ServicePlan],
        shutdownContext: ProjectShutdownContext,
        mode: TerminalMode,
        machineContext: MachineContext = .applicationSandbox,
        stopProject: @Sendable (ProjectShutdownContext) async throws -> Void = {
            try await ProjectShutdown.stop(context: $0)
        }
    ) async throws {
        guard !plans.isEmpty else { return }

        let sources = makeLogSources(from: plans)
        let options = LogStreamOptions(
            tail: nil,
            follow: true,
            boot: false,
            mode: mode,
            machineContext: machineContext
        )
        let containerIDs = plans.map(\.name)

        let outcome = try await LogFollowSession.runUntilCancelled(
            sources: sources,
            options: options,
            policy: .stopProject(shutdownContext),
            stopProject: stopProject,
            parallelUntilComplete: {
                try await ContainerExitWatch.waitUntilAllStopped(
                    ids: containerIDs,
                    status: ContainerExitWatch.statusProvider(machineContext: machineContext)
                )
            },
            onMultiplexError: { error in
                fputs(
                    "Warning: couldn't follow service logs: \(error.localizedDescription).\n",
                    stderr
                )
            }
        )

        if case .interrupted(let signal) = outcome {
            throw ExitCode(signal.exitCode)
        }
    }
}
