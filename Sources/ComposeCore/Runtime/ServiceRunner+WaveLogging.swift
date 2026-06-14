import Foundation

extension ServiceRunner {
    package static func logWaveStart(
        wave: Int,
        total: Int,
        project: String,
        containerNames: [String]
    ) {
        OsLogTelemetry.enabled {
            OsLogTelemetry.orchestration.info(
                """
                event=wave_start wave=\(wave, privacy: .public) total=\(total, privacy: .public) \
                project=\(project, privacy: .public) \
                containers=\(containerNames.joined(separator: ","), privacy: .public)
                """
            )
        }
    }

    package static func logWaveComplete(wave: Int, project: String) {
        OsLogTelemetry.enabled {
            OsLogTelemetry.orchestration.info(
                "event=wave_complete wave=\(wave, privacy: .public) project=\(project, privacy: .public)"
            )
        }
    }

    package static func logWaveFailure(
        wave: Int,
        project: String,
        failures: [(service: String, error: Error)]
    ) {
        guard !failures.isEmpty else { return }
        OsLogTelemetry.enabled {
            let summary = failures.map {
                "\($0.service):\(String(describing: type(of: $0.error)))"
            }.joined(separator: ",")
            OsLogTelemetry.orchestration.error(
                """
                event=wave_failure wave=\(wave, privacy: .public) project=\(project, privacy: .public) \
                failures=\(summary, privacy: .public)
                """
            )
        }
    }
}
