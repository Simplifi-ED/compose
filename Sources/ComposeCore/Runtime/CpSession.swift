import ContainerAPIClient
import ContainerResource
import Foundation

package enum CpSession {
    package enum Direction: Sendable, Equatable {
        case copyIn
        case copyOut
    }

    package typealias CopyIn = ContainerCopyAPI.CopyIn
    package typealias CopyOut = ContainerCopyAPI.CopyOut
    package typealias GetContainer = ContainerCopyAPI.GetContainer

    package struct Configuration: Sendable {
        package let direction: Direction
        package let targets: [ProjectContainer]
        package let projectName: String
        package let serviceName: String
        package let containerPath: String
        package let hostPath: String
        package let rawHostPath: String

        package init(
            direction: Direction,
            targets: [ProjectContainer],
            projectName: String,
            serviceName: String,
            containerPath: String,
            hostPath: String,
            rawHostPath: String
        ) {
            self.direction = direction
            self.targets = targets
            self.projectName = projectName
            self.serviceName = serviceName
            self.containerPath = containerPath
            self.hostPath = hostPath
            self.rawHostPath = rawHostPath
        }
    }

    package static func run(
        configuration: Configuration,
        machineContext: MachineContext = .applicationSandbox,
        copyIn: CopyIn? = nil,
        copyOut: CopyOut? = nil,
        getContainer: GetContainer? = nil
    ) async throws {
        let resolvedCopyIn = copyIn ?? { id, source, destination, mode, createParents in
            try await ContainerCopyAPI.copyIn(
                id: id,
                source: source,
                destination: destination,
                mode: mode,
                createParents: createParents,
                machineContext: machineContext
            )
        }
        let resolvedCopyOut = copyOut ?? { id, source, destination, createParents in
            try await ContainerCopyAPI.copyOut(
                id: id,
                source: source,
                destination: destination,
                createParents: createParents,
                machineContext: machineContext
            )
        }
        let resolvedGetContainer = getContainer ?? { id in
            try await ContainerCopyAPI.get(id: id, machineContext: machineContext)
        }
        try await preflightTargets(configuration: configuration, getContainer: resolvedGetContainer)

        if configuration.targets.count == 1 {
            try await copyToTarget(
                configuration: configuration,
                containerName: configuration.targets[0].name,
                copyIn: resolvedCopyIn,
                copyOut: resolvedCopyOut
            )
            return
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for target in configuration.targets {
                let containerName = target.name
                group.addTask {
                    try await copyToTarget(
                        configuration: configuration,
                        containerName: containerName,
                        copyIn: resolvedCopyIn,
                        copyOut: resolvedCopyOut
                    )
                }
            }
            try await group.waitForAll()
        }
    }

    private static func preflightTargets(
        configuration: Configuration,
        getContainer: @escaping GetContainer
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for target in configuration.targets {
                group.addTask {
                    let snapshot = try await getContainer(target.name)
                    try ComposeContainerGuard.verifyRunningProjectService(
                        snapshot: snapshot,
                        containerName: target.name,
                        projectName: configuration.projectName,
                        serviceName: configuration.serviceName
                    )
                }
            }
            try await group.waitForAll()
        }
    }

    private static func copyToTarget(
        configuration: Configuration,
        containerName: String,
        copyIn: CopyIn,
        copyOut: CopyOut
    ) async throws {
        switch configuration.direction {
        case .copyIn:
            try await performCopyIn(
                containerName: containerName,
                containerPath: configuration.containerPath,
                hostPath: configuration.hostPath,
                rawHostPath: configuration.rawHostPath,
                copyIn: copyIn
            )
        case .copyOut:
            try await performCopyOut(
                containerName: containerName,
                containerPath: configuration.containerPath,
                hostPath: configuration.hostPath,
                rawHostPath: configuration.rawHostPath,
                copyOut: copyOut
            )
        }
    }

    private static func performCopyIn(
        containerName: String,
        containerPath: String,
        hostPath: String,
        rawHostPath: String,
        copyIn: CopyIn
    ) async throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: hostPath, isDirectory: &isDirectory) else {
            throw ComposeError.cpSourceNotFound(path: rawHostPath)
        }
        if rawHostPath.hasSuffix("/"), !isDirectory.boolValue {
            throw ComposeError.invalidCpPath(
                reason: "source path is not a directory: \(rawHostPath)"
            )
        }

        let mode: UInt32 = isDirectory.boolValue ? 0o755 : 0o644
        try await copyIn(
            containerName,
            hostPath,
            containerPath,
            mode,
            true
        )
    }

    private static func performCopyOut(
        containerName: String,
        containerPath: String,
        hostPath: String,
        rawHostPath: String,
        copyOut: CopyOut
    ) async throws {
        let destPath = (hostPath as NSString).standardizingPath
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: destPath, isDirectory: &isDirectory)

        if exists, isDirectory.boolValue {
            let lastComponent = (containerPath as NSString).lastPathComponent
            guard !lastComponent.isEmpty else {
                throw ComposeError.invalidCpPath(
                    reason: "container source path has no file name: \(containerPath)"
                )
            }
            let finalDest = (destPath as NSString).appendingPathComponent(lastComponent)
            try await copyOut(containerName, containerPath, finalDest, true)
        } else if rawHostPath.hasSuffix("/") {
            if exists, !isDirectory.boolValue {
                throw ComposeError.invalidCpPath(
                    reason: "destination is not a directory: \(rawHostPath)"
                )
            }
            try await copyOut(containerName, containerPath, destPath, true)
        } else {
            try await copyOut(containerName, containerPath, destPath, true)
        }
    }

}
