import Foundation

extension Up {
    struct DryRunInput: Sendable {
        let projectName: String
        let composeFile: ComposeFile
        let layers: [[ServicePlan]]
        let healthContext: HealthWaitContext
        let buildPlans: [BuildRunner.Plan]
        let networkPlans: [NetworkPlanning.Plan]
        let volumePlans: [VolumePlanning.Plan]
        let fileURLs: [URL]
        let machineContext: MachineContext
        let installHostDNS: Bool
    }

    func runDryRun(_ input: DryRunInput) async throws {
        let manifest = DryRunManifest(machineName: input.machineContext.machineName)
        let execution = WaveExecutionPolicy(maxConcurrent: parallelOptions.resolvedMaxConcurrent())

        try await executeBuildPlans(
            input.buildPlans,
            dryRunManifest: manifest,
            machineContext: input.machineContext
        )
        try await NetworkRunner.createAll(
            input.networkPlans,
            projectName: input.projectName,
            dryRunManifest: manifest,
            machineContext: input.machineContext
        )
        try await VolumeRunner.createAll(
            input.volumePlans,
            projectName: input.projectName,
            dryRunManifest: manifest,
            machineContext: input.machineContext
        )

        try await recordDryRunHostDNSIfRequested(input, manifest: manifest)

        if workspaceHygiene.shouldRemoveOrphans {
            try await recordOrphanTeardowns(
                manifest: manifest,
                projectName: input.projectName,
                composeFile: input.composeFile,
                machineContext: input.machineContext
            )
        }

        let hooks = await manifest.makeUpHooks(machineContext: input.machineContext)
        try await ServiceRunner.up(
            layers: input.layers,
            healthContext: input.healthContext,
            hooks: hooks,
            execution: execution,
            beforeWave: { index in
                await manifest.setUpWaveIndex(index)
            }
        )
        await manifest.printLines()
    }

    func recordOrphanTeardowns(
        manifest: DryRunManifest,
        projectName: String,
        composeFile: ComposeFile,
        machineContext: MachineContext
    ) async throws {
        let discovered: [DiscoveredContainer]
        do {
            discovered = try await ContainerDiscovery.containers(
                forProject: projectName,
                machineContext: machineContext
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            WorkspaceHygieneOutput.warnOrphanRemovalSkipped(
                WorkspaceHygieneOutput.listContainersFailureMessage(error)
            )
            return
        }
        let orphans = OrphanRemoval.orphans(
            in: discovered,
            composeFile: composeFile,
            policy: .beforeUp(activeProfiles: profileOptions.activeProfileSet)
        )
        for orphan in orphans {
            await manifest.recordTeardown(orphan.name, reason: .orphan)
        }
    }
}

private extension Up {
    func recordDryRunHostDNSIfRequested(_ input: DryRunInput, manifest: DryRunManifest) async throws {
        guard input.installHostDNS else { return }
        let activeServiceNames = Set(input.layers.flatMap { $0 }.map(\.serviceName))
        try await HostDNSMapping.installAll(
            composeFile: input.composeFile,
            projectName: input.projectName,
            firstComposeFileURL: input.fileURLs[0],
            activeServiceNames: activeServiceNames,
            dryRunManifest: manifest
        )
        guard HostDNSPlanning.hasBridgeHostDeclarations(
            composeFile: input.composeFile,
            activeServiceNames: activeServiceNames
        ) else {
            return
        }
        try await HostDNSMapping.refreshBridgeMappings(
            composeFile: input.composeFile,
            projectName: input.projectName,
            firstComposeFileURL: input.fileURLs[0],
            activeServiceNames: activeServiceNames,
            serviceAddresses: bridgeHostDNSDryRunAddresses(
                composeFile: input.composeFile,
                activeServiceNames: activeServiceNames
            ),
            dryRunManifest: manifest
        )
    }

    func bridgeHostDNSDryRunAddresses(
        composeFile: ComposeFile,
        activeServiceNames: Set<String>
    ) -> [String: String] {
        var result: [String: String] = [:]
        for serviceName in activeServiceNames {
            guard let service = composeFile.services[serviceName],
                  !service.hostnames.isEmpty,
                  NetworkPlanning.serviceUsesBridgeNetwork(composeFile: composeFile, service: service)
            else {
                continue
            }
            result[serviceName] = "0.0.0.0"
        }
        return result
    }
}
