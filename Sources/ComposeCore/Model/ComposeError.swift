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
                + "Add \(name) to .env beside the compose file."
        case .rollbackFailed(let started, let failures):
            let startedList = started.joined(separator: ", ")
            let details = failures.map { "'\($0.container)': \($0.error.localizedDescription)" }.joined(separator: "; ")
            return "Startup failed and rollback couldn't remove all containers (started: \(startedList)): \(details)"
        }
    }
}
