import Foundation

extension HostDNSMapping {
    static func resolveIdentity(
        projectName: String,
        firstComposeFileURL: URL?
    ) -> HostDNSPlanning.BlockIdentity? {
        if let record = readOwnership(projectName: projectName) {
            return HostDNSPlanning.BlockIdentity(
                projectName: record.projectName,
                projectID: record.projectID,
                composeFilePath: record.composeFilePath
            )
        }
        guard let firstComposeFileURL else { return nil }
        return HostDNSPlanning.blockIdentity(
            projectName: projectName,
            firstComposeFileURL: firstComposeFileURL
        )
    }

    static func installLive(
        identity: HostDNSPlanning.BlockIdentity,
        planned: [HostDNSPlanning.Plan]
    ) throws {
        try HostsFileEditor.withHostsLock {
            let hostsContent = try HostsFileEditor.readHostsFile()
            _ = try HostDNSPlanning.validateExternalConflicts(
                plans: planned,
                hostsContent: hostsContent,
                projectID: identity.projectID,
                strict: true
            )
            warnSameNameDifferentID(content: hostsContent, identity: identity)
            let merged = HostsFileEditor.mergeBlock(
                content: hostsContent,
                identity: identity,
                hostnames: planned.map(\.hostname)
            )
            try HostsFileEditor.apply(mergedContent: merged)
        }
        do {
            try writeOwnership(
                identity: identity,
                hostnames: planned.map(\.hostname)
            )
        } catch {
            removeLive(identity: identity, projectName: identity.projectName)
            throw error
        }
        fputs(
            "Installed host DNS for \(planned.count) hostname(s) "
                + "(project \(identity.projectName), id \(identity.projectID)).\n",
            stderr
        )
    }

    static func removeLive(identity: HostDNSPlanning.BlockIdentity, projectName: String) {
        do {
            try HostsFileEditor.withHostsLock {
                let hostsContent = try HostsFileEditor.readHostsFile()
                let merged = HostsFileEditor.removeBlock(content: hostsContent, projectID: identity.projectID)
                if merged == hostsContent {
                    removeOwnership(projectName: projectName)
                    return
                }
                try HostsFileEditor.apply(
                    mergedContent: merged,
                    requiresManagedBlock: false,
                    privilegedApply: { tempURL, hostsPath in
                        try HostsFileEditor.defaultPrivilegedApply(
                            tempURL: tempURL,
                            hostsPath: hostsPath,
                            operation: "remove"
                        )
                    }
                )
            }
            removeOwnership(projectName: projectName)
        } catch let error as ComposeError {
            handleRemovalComposeError(error, identity: identity)
        } catch {
            warnRemovalFailed(identity: identity, reason: error.localizedDescription)
        }
    }

    static func handleRemovalComposeError(_ error: ComposeError, identity: HostDNSPlanning.BlockIdentity) {
        switch error {
        case .hostDNSElevationCancelled:
            warnRemovalFailed(identity: identity, reason: error.localizedDescription)
        case .hostDNSRequiresElevation(let manualCommand):
            warnRemovalFailed(identity: identity, reason: error.localizedDescription, manualCommand: manualCommand)
        default:
            warnRemovalFailed(identity: identity, reason: error.localizedDescription)
        }
    }
}
