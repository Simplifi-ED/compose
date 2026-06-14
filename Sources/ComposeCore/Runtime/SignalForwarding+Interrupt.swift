import Foundation

extension SignalForwarding {
    static func stopProjectAfterInterrupt(
        context: ProjectShutdownContext,
        signal: InterruptSignal,
        stopProject: @Sendable (ProjectShutdownContext) async throws -> Void
    ) async -> ExitOutcome {
        let policy = policyLabel(.stopProject(context))
        OsLogTelemetry.enabled {
            OsLogTelemetry.signals.info(
                """
                event=signal_shutdown_start policy=\(policy, privacy: .public) \
                project=\(context.projectName, privacy: .public)
                """
            )
        }
        do {
            try await stopProject(context)
        } catch {
            OsLogTelemetry.enabled {
                OsLogTelemetry.signals.error(
                    """
                    event=signal_shutdown_failed policy=\(policy, privacy: .public) \
                    project=\(context.projectName, privacy: .public) \
                    error_type=\(String(describing: type(of: error)), privacy: .public)
                    """
                )
            }
            fputs(
                """
                Warning: couldn't stop all project containers after interrupt: \
                \(error.localizedDescription).\n
                """,
                stderr
            )
        }
        return .interrupted(signal)
    }

    static func stopRunContainerAfterInterrupt(
        context: RunShutdownContext,
        signal: InterruptSignal,
        stopRunContainer: @Sendable (RunShutdownContext) async throws -> Void
    ) async -> ExitOutcome {
        let policy = policyLabel(.stopRunContainer(context))
        OsLogTelemetry.enabled {
            OsLogTelemetry.signals.info(
                """
                event=signal_shutdown_start policy=\(policy, privacy: .public) \
                project=\(context.projectName, privacy: .public) \
                container=\(context.containerID, privacy: .public)
                """
            )
        }
        do {
            try await stopRunContainer(context)
        } catch {
            OsLogTelemetry.enabled {
                OsLogTelemetry.signals.error(
                    """
                    event=signal_shutdown_failed policy=\(policy, privacy: .public) \
                    project=\(context.projectName, privacy: .public) \
                    container=\(context.containerID, privacy: .public) \
                    error_type=\(String(describing: type(of: error)), privacy: .public)
                    """
                )
            }
            fputs(
                """
                Warning: couldn't stop run container after interrupt: \
                \(error.localizedDescription).\n
                """,
                stderr
            )
        }
        return .interrupted(signal)
    }
}
