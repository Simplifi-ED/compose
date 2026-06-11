import Foundation

public enum ComposeError: LocalizedError, Sendable {
    case fileNotFound(String)
    case readFailed(String, underlying: Error)
    case parseFailed(String, underlying: Error)
    case noServices
    case missingImage(service: String)
    case invalidField(String, reason: String)
    case unsupportedPort(String)
    case unsupportedVolume(String)
    case unsupportedVolumeOption(String)
    case unsupportedNamedVolume(String)
    case volumeHostPathNotFound(path: String)
    case serviceFailed(service: String, underlying: Error)
    case multipleServiceFailures([(service: String, error: Error)])
    case unknownDependency(service: String, dependency: String)
    case profileExcludedDependency(service: String, dependency: String, requiredProfiles: [String])
    case profileFilterRequiresComposeFile
    case circularDependency(services: [String])
    case unresolvedVariable(name: String, composePath: String)
    case rollbackFailed(started: [String], failures: [(container: String, error: Error)])
    case invalidProjectName(String)
    case invalidComposeFilePath(String)
    case undefinedService(service: String)
    case serviceNotFound(service: String, project: String)
    case serviceNotRunning(service: String, state: String)
    case ambiguousService(service: String, containers: [String])
    case containerProjectMismatch(container: String, project: String)
    case invalidScaleSpec(String)
    case replicasBelowMinimum(service: String, count: Int)
    case containerNameNotSupportedWithReplicas(service: String, containerName: String)
    case staticPortBlocksScaling(service: String, port: String, replicas: Int)
    case scaleServiceRequiresProfile(service: String, requiredProfiles: [String])

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
            return "Service '\(service)' is missing an image. Add an image and try again."
        case .invalidField(let field, let reason):
            return "Invalid \(field): \(reason)."
        case .unsupportedPort(let port):
            return "Unsupported port mapping '\(port)'. Use host:container, host:container/tcp, "
                + "or a container-only port like '80'."
        case .unsupportedVolume(let volume):
            return "Unsupported volume mapping '\(volume)'. Use host:container (for example ./data:/app/data)."
        case .unsupportedVolumeOption(let volume):
            return "Volume options aren't supported yet. Use host:container without a suffix (got '\(volume)')."
        case .unsupportedNamedVolume(let volume):
            return "Named volumes aren't supported. Use a host path like ./data:/app/data (got '\(volume)')."
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
            let flags = requiredProfiles.map { "--profile \($0)" }.joined(separator: " or ")
            return "Service '\(service)' depends on '\(dependency)', which only starts with \(flags). "
                + "Pass \(flags) or remove the dependency."
        case .profileFilterRequiresComposeFile:
            return "Using --profile requires a compose file. Pass -f or run from a directory with compose.yaml."
        case .circularDependency(let services):
            let path = services.joined(separator: " → ")
            return "Circular dependency: \(path). Remove or reorder depends_on entries."
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
            return "No container for service '\(service)' in project '\(project)'. Check the service name and run compose up."
        case .serviceNotRunning(let service, let state):
            return "Service '\(service)' isn't running (state: \(state)). Start it with compose up."
        case .ambiguousService(let service, let containers):
            let names = containers.joined(separator: ", ")
            return "Service '\(service)' is running multiple replicas (\(names)). "
                + "Replica selection isn't supported yet; pick one with 'container exec CONTAINER COMMAND'."
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
            let flags = requiredProfiles.map { "--profile \($0)" }.joined(separator: " or ")
            return "Service '\(service)' only starts with \(flags). Pass \(flags) to scale it."
        }
    }
}
