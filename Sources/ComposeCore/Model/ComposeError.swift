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
            return "Unsupported port mapping '\(port)'. Use host:container or host:container/tcp."
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
            return "Service '\(service)' matches multiple containers (\(names)). Scale isn't supported yet."
        case .containerProjectMismatch(let container, let project):
            return "Container '\(container)' isn't part of project '\(project)'."
        }
    }
}
