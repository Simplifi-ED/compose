import ArgumentParser
import Foundation

public struct Cp: AsyncParsableCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        abstract: "Copy files between the host and a running service container."
    )

    @OptionGroup
    var projectOptions: ProjectOptions

    @OptionGroup
    var dryRunOptions: DryRunOptions

    @OptionGroup
    var machineOptions: MachineOptions

    @Option(
        name: .long,
        help: "1-based replica index when a service runs multiple containers (for example 2 for demo_web_2)."
    )
    var index: Int?

    @Flag(
        name: .long,
        help: "Copy into every running replica (host to container only)."
    )
    var all = false

    @Argument(help: "Source path (SERVICE:/path or local path).")
    var source: String

    @Argument(help: "Destination path (SERVICE:/path or local path).")
    var destination: String

    public func validate() throws {
        if let index, index < 1 {
            throw ValidationError("--index must be 1 or greater.")
        }
        if index != nil, all {
            throw ValidationError("Use either --index or --all, not both.")
        }
    }

    public func run() async throws {
        let srcRef = try CpPathRef.parse(source)
        let dstRef = try CpPathRef.parse(destination)

        switch (srcRef, dstRef) {
        case (.service, .service):
            throw ComposeError.cpContainerToContainer
        case (.local, .local):
            throw ComposeError.cpLocalToLocal
        case (.service, .local):
            try await runCopy(direction: .copyOut, localRef: dstRef, serviceRef: srcRef)
        case (.local, .service):
            try await runCopy(direction: .copyIn, localRef: srcRef, serviceRef: dstRef)
        }
    }

    private enum CopyDirection {
        case copyIn
        case copyOut
    }

    private func runCopy(
        direction: CopyDirection,
        localRef: CpPathRef,
        serviceRef: CpPathRef
    ) async throws {
        guard case .local(let rawHostPath) = localRef,
              case .service(let serviceName, let containerPath) = serviceRef else { return }
        if direction == .copyOut, all { throw ComposeError.cpAllRequiresCopyIn }

        let validatedContainerPath = try CpPathValidator.validateContainerPath(containerPath)
        let hostRole: CpPathValidator.HostPathRole = direction == .copyIn ? .source : .destination
        let resolvedHost = try CpPathValidator.resolveHostPath(rawHostPath, role: hostRole)

        let machineContext = try await machineOptions.resolveContext()
        let context = try projectOptions.resolvedLabelCommandContext(
            skipComposeFileOnExplicitProject: true,
            machineContext: machineContext
        )
        let containers = try await ContainerDiscovery.projectContainers(
            forProject: context.projectName,
            machineContext: machineContext
        )
        let targets = try CpContainerResolver.resolve(
            projectName: context.projectName,
            serviceName: serviceName,
            containers: containers,
            index: index,
            all: direction == .copyIn && all
        )

        let sessionDirection: CpSession.Direction = direction == .copyIn ? .copyIn : .copyOut
        let dryRunSource = direction == .copyIn ? rawHostPath : validatedContainerPath
        let dryRunDestination = direction == .copyIn ? validatedContainerPath : rawHostPath

        if dryRunOptions.isEnabled {
            await printCpDryRun(
                manifest: DryRunManifest(machineName: machineContext.machineName),
                targets: targets,
                direction: sessionDirection,
                source: dryRunSource,
                destination: dryRunDestination
            )
            return
        }

        try await CpSession.run(
            configuration: CpSession.Configuration(
                direction: sessionDirection,
                targets: targets,
                projectName: context.projectName,
                serviceName: serviceName,
                containerPath: validatedContainerPath,
                hostPath: resolvedHost.path,
                rawHostPath: rawHostPath
            ),
            machineContext: machineContext
        )
    }
}
