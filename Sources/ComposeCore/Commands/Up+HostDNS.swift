import Foundation

extension Up {
    func installHostDNSAfterStartupIfRequested(
        _ input: LiveInput,
        machineContext: MachineContext
    ) async {
        guard input.installHostDNS else { return }
        let activeServiceNames = Set(input.plan.plans.map(\.serviceName))
        do {
            try await HostDNSMapping.installAfterStartup(
                composeFile: input.plan.composeFile,
                projectName: input.plan.projectName,
                firstComposeFileURL: input.plan.fileURLs[0],
                activeServiceNames: activeServiceNames,
                listContainers: {
                    try await ContainerDiscovery.projectContainers(
                        forProject: input.plan.projectName,
                        machineContext: machineContext
                    )
                }
            )
        } catch let error as ComposeError {
            switch error {
            case .hostDNSElevationCancelled:
                fputs(
                    "Warning: Host DNS install cancelled. Containers are running without host mappings.\n",
                    stderr
                )
            default:
                fputs(
                    "Warning: Host DNS install failed: \(error.localizedDescription)\n",
                    stderr
                )
            }
        } catch {
            fputs(
                "Warning: Host DNS install failed: \(error.localizedDescription)\n",
                stderr
            )
        }
    }
}
