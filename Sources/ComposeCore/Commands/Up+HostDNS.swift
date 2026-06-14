import ArgumentParser
import Foundation

extension Up {
    func installHostDNSIfRequested(_ input: LiveInput) async throws {
        guard input.installHostDNS else { return }
        do {
            try await HostDNSMapping.installAll(
                composeFile: input.composeFile,
                projectName: input.projectName,
                firstComposeFileURL: input.fileURLs[0],
                activeServiceNames: Set(input.plans.map(\.serviceName))
            )
        } catch let error as ComposeError {
            switch error {
            case .hostDNSElevationCancelled:
                fputs(
                    """
                    Warning: Host DNS install cancelled. Containers will start without host mappings.\n
                    """,
                    stderr
                )
            default:
                throw error
            }
        }
    }

    func rollbackHostDNSIfNeeded(_ input: LiveInput, unless error: Error) async {
        guard input.installHostDNS else { return }
        if error is ExitCode { return }
        await HostDNSMapping.removeProjectMappings(
            projectName: input.projectName,
            firstComposeFileURL: input.fileURLs[0]
        )
    }
}
