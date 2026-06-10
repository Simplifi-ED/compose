import Foundation

public enum ComposeError: LocalizedError, Sendable {
    case fileNotFound(String)
    case readFailed(String, underlying: Error)
    case parseFailed(String, underlying: Error)
    case noServices
    case missingImage(service: String)
    case invalidField(String, reason: String)
    case unsupportedPort(String)
    case serviceFailed(service: String, underlying: Error)
    case multipleServiceFailures([(service: String, error: Error)])

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
        case .serviceFailed(let service, let underlying):
            return "Service '\(service)' failed: \(underlying.localizedDescription)"
        case .multipleServiceFailures(let failures):
            let details = failures.map { "'\($0.service)': \($0.error.localizedDescription)" }.joined(separator: "; ")
            return "One or more services failed: \(details)"
        }
    }
}
