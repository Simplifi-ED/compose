import Foundation

extension ComposeError {
    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Compose file not found at \(path). Check the path and try again."
        case .readFailed(let path, let underlying):
            return "Couldn't read \(path): \(underlying.localizedDescription)"
        case .parseFailed(let path, let underlying):
            return "Couldn't parse \(path): \(underlying.localizedDescription)"
        case .noServices:
            return "The compose file doesn't define any services."
        case .missingImage(let service):
            return "Service '\(service)' needs an image or build block."
        case .buildContextNotFound(let path, let service):
            return "Build context '\(path)' doesn't exist for service '\(service)'. "
                + "Create the directory or fix build.context."
        case .buildDockerfileNotFound(let path, let service):
            return "Dockerfile '\(path)' doesn't exist for service '\(service)'."
        case .buildFailed(let service, let underlying):
            return "Build for '\(service)' failed: \(underlying.localizedDescription)"
        case .invalidField(let field, let reason):
            return "Invalid \(field): \(reason)."
        case .unsupportedPort(let port):
            return "Unsupported port mapping '\(port)'. Use host:container, host:container/tcp, "
                + "or a container-only port like '80'."
        case .unsupportedVolume(let volume):
            return "Unsupported volume mapping '\(volume)'. Use host:container "
                + "(for example ./data:/app/data) or host:container:ro for read-only bind mounts "
                + "(comma options like :ro,z are supported)."
        case .unsupportedVolumeOption(let volume):
            return "Unsupported bind-mount option in '\(volume)'. "
                + "Use ':ro', ':z', or comma-separated options like ':ro,z'."
        case .unsupportedExternalVolume(let name):
            return "External volumes aren't supported. Remove external: true from volume '\(name)' "
                + "to let compose create it as a project-scoped volume."
        case .undefinedVolume(let service, let volume):
            return "Volume '\(volume)' isn't defined in volumes:. "
                + "Add it at the root or remove the reference from service '\(service)'."
        case .invalidVolumeName(let volume, let runtimeName):
            return "Volume '\(volume)' maps to runtime name '\(runtimeName)', which isn't valid. "
                + "Use letters, numbers, dots, hyphens, or underscores."
        case .includeVolumeConflict(let name, let includePath, let definedIn):
            return "Volume '\(name)' is already defined in \(definedIn). "
                + "\(includePath) also defines '\(name)'. Rename one entry or remove the duplicate include."
        case .volumeCreateFailed(let volume, let underlying):
            return "Couldn't create volume '\(volume)': \(underlying.localizedDescription)"
        case .volumeHostPathNotFound(let path):
            return "Host path '\(path)' doesn't exist. Create the path or fix the volume mapping."
        case .serviceFailed(let service, let underlying):
            return "Service '\(service)' failed: \(underlying.localizedDescription)"
        case .multipleServiceFailures(let failures):
            let details = failures.map { "'\($0.service)': \($0.error.localizedDescription)" }.joined(separator: "; ")
            return "One or more services failed: \(details)"
        case .unknownDependency(let service, let dependency):
            return "Service '\(service)' depends on '\(dependency)', "
                + "which isn't defined. Check service names in depends_on."
        case .profileExcludedDependency(let service, let dependency, let requiredProfiles):
            let names = Self.profileNamesDescription(requiredProfiles)
            let options = Self.profileActivationOptions(requiredProfiles)
            return "Service '\(service)' depends on '\(dependency)', which requires profile \(names). "
                + "Enable it with \(options), or remove the dependency."
        case .profileFilterRequiresComposeFile:
            return "Profile filtering requires a compose file. Pass -f or run from a directory with compose.yaml."
        case .circularDependency(let services):
            let path = services.joined(separator: " → ")
            return "Circular dependency: \(path). Remove or reorder depends_on entries."
        case .circularInclude(let chain):
            let path = chain.joined(separator: " → ")
            return "Circular include: \(path). Remove one include entry to break the loop."
        case .includeConflict(let service, let includePath, let definedIn):
            return "Service '\(service)' is already defined in \(definedIn). "
                + "\(includePath) also defines '\(service)'. Rename one service or remove the duplicate include."
        case .invalidInclude(let reason):
            return "Invalid include: \(reason)."
        case .unresolvedVariable(let name, let composePath):
            return "Unresolved variable '${name}' in \(composePath). "
                + "Set \(name) in the shell environment or .env beside the compose file, "
                + "or use ${\(name):-default} / ${\(name)-default} for a fallback."
        case .rollbackFailed(let started, let failures):
            let startedList = started.joined(separator: ", ")
            let details = failures.map { "'\($0.container)': \($0.error.localizedDescription)" }.joined(separator: "; ")
            return "Startup failed and rollback couldn't remove all containers (started: \(startedList)): \(details)"
        case .invalidProjectName(let name):
            return "Invalid project name '\(name)'. Use lowercase letters, numbers, dashes, and underscores."
        case .invalidComposeFilePath(let path):
            return "Invalid compose file path '\(path)'. Expected a regular file."
        case .undefinedService(let service):
            return "Service '\(service)' isn't defined in the compose file. Check the service name."
        case .serviceNotFound(let service, let project):
            return """
                No container for service '\(service)' in project '\(project)'. \
                Check the service name and run compose up.
                """
        case .containerNotFound(let container):
            return "Container '\(container)' not found. Check the name with compose ps."
        case .serviceNotRunning(let service, let state):
            return "Service '\(service)' isn't running (state: \(state)). Start it with compose up."
        case .ambiguousService(let service, let containers):
            let names = containers.joined(separator: ", ")
            return "Service '\(service)' is running multiple replicas (\(names)). "
                + "Use compose cp --index N, or pick a container with 'container exec CONTAINER COMMAND'."
        case .containerProjectMismatch(let container, let project):
            return "Container '\(container)' isn't part of project '\(project)'."
        case .invalidScaleSpec(let value):
            return "Invalid --scale value '\(value)'. Use SERVICE=COUNT with a count of 1 or more (for example web=3)."
        case .replicasBelowMinimum(let service, let count):
            return "Service '\(service)' sets replicas: \(count). Use a replica count of 1 or more."
        case .containerNameNotSupportedWithReplicas(let service, let containerName):
            return "Service '\(service)' sets container_name '\(containerName)', which conflicts with "
                + "indexed container names. Remove container_name to start the service with compose up."
        case .staticPortBlocksScaling(let service, let port, let replicas):
            return "Service '\(service)' can't scale to \(replicas) replicas with port '\(port)'. "
                + "Each replica would bind the same host port. "
                + "Remove the host port (for example '80' instead of '8080:80') or set replicas to 1."
        case .scaleServiceRequiresProfile(let service, let requiredProfiles):
            let names = Self.profileNamesDescription(requiredProfiles)
            let options = Self.profileActivationOptions(requiredProfiles)
            return "Service '\(service)' requires profile \(names). Enable it with \(options) to scale it."
        case .healthCheckTimeout(let dependency, let container):
            return "Service '\(dependency)' didn't become healthy in time (container '\(container)'). "
                + "Check logs with compose logs \(dependency)."
        case .serviceStartTimeout(let dependency, let container):
            return "Service '\(dependency)' didn't start in time (container '\(container)'). "
                + "Check logs with compose logs \(dependency)."
        case .unsupportedExternalResource(let kind):
            return "External \(kind.rootFieldName) aren't supported. Use a local file: path with external: false."
        case .undefinedResource(let name, let kind):
            return "\(kind.rootFieldName.capitalized) '\(name)' isn't defined. "
                + "Add it under \(kind.rootFieldName): or fix the service reference."
        case .resourceFileNotFound(let path, let kind):
            return "\(kind.rootFieldName.capitalized) file '\(path)' doesn't exist. "
                + "Create the file or fix the \(kind.rootFieldName) definition."
        case .includeResourceConflict(let name, let kind, let includePath, let definedIn):
            return "\(kind.rootFieldName.capitalized) '\(name)' is already defined in \(definedIn). "
                + "\(includePath) also defines '\(name)'. Rename one entry or remove the duplicate include."
        case .unsupportedExternalNetwork(let name):
            return "External networks aren't supported. Remove external: true from network '\(name)' "
                + "to let compose create it as a project-scoped network."
        case .unsupportedNetworkOption(let network, let option):
            return "Network option '\(option)' on '\(network)' isn't supported. "
                + "Use a plain membership entry like 'networks: [\(network)]'."
        case .undefinedNetwork(let service, let network):
            return "Network '\(network)' isn't defined in networks:. "
                + "Add it at the root or remove the reference from service '\(service)'."
        case .invalidNetworkName(let network, let runtimeName):
            return "Network '\(network)' maps to runtime name '\(runtimeName)', which isn't valid. "
                + "Use up to 63 lowercase letters, numbers, dots, hyphens, or underscores."
        case .includeNetworkConflict(let name, let includePath, let definedIn):
            return "Network '\(name)' is already defined in \(definedIn). "
                + "\(includePath) also defines '\(name)'. Rename one entry or remove the duplicate include."
        case .networkCreateFailed(let network, let underlying):
            return "Couldn't create network '\(network)': \(underlying.localizedDescription)"
        case .networksRequireMacOS26:
            return "Custom networks require macOS 26 or newer. "
                + "Remove networks: from the compose file, or upgrade macOS."
        case .invalidCpPath(let reason):
            return "Invalid cp path: \(reason)."
        case .cpHostPathOutsideCWD(let path):
            return "Host path '\(path)' resolves outside the current directory."
        case .cpSourceNotFound(let path):
            return "Host path '\(path)' doesn't exist."
        case .cpContainerToContainer:
            return "Can't copy between two containers. Copy through the host instead."
        case .cpLocalToLocal:
            return "One side must be a service reference (SERVICE:/path)."
        case .cpAllRequiresCopyIn:
            return "Can't use --all when copying from a container to the host. Use --index to pick a replica."
        case .replicaNotFound(let service, let index, let project):
            return "No running replica \(index) for service '\(service)' in project '\(project)'. "
                + "Check compose ps."
        case .invalidMachineName(let name):
            return "Invalid machine name '\(name)'. Use lowercase letters, numbers, and hyphens."
        case .machineNotFound(let name):
            return "Container machine '\(name)' not found. Run `container machine list` to see machines."
        case .machineStopped(let name, let reason):
            return reason.message(machineName: name)
        case .machineNotRunning(let name):
            return """
                Container machine '\(name)' isn't running. `compose up` and `compose down` boot it \
                when stopped; start it manually with `container machine run -n \(name)` if boot failed.
                """
        case .machineBootFailed(let name, let underlying):
            return "Couldn't boot container machine '\(name)': \(underlying.localizedDescription)"
        case .machineUnsupportedCommand(let command):
            return "The \(command) command doesn't support --machine."
        case .machineUnsupportedOperation(let operation):
            return "Machine mode doesn't support \(operation) yet."
        case .machineCommandFailed(let machine, let command, let exitCode):
            return "Command failed in container machine '\(machine)' (exit \(exitCode)): \(command)"
        }
    }

    fileprivate static func profileNamesDescription(_ profiles: [String]) -> String {
        profiles.map { "'\($0)'" }.joined(separator: " or ")
    }

    fileprivate static func profileActivationOptions(_ profiles: [String]) -> String {
        let flags = profiles.map { "--profile \($0)" }.joined(separator: " ")
        let envValue = profiles.joined(separator: ",")
        return "\(flags) or COMPOSE_PROFILES=\(envValue)"
    }
}
