import ContainerAPIClient
import ContainerCommands
import ContainerizationError
import ContainerResource
import Foundation

public enum ContainerTeardown {
    public static func teardown(id: String) async throws {
        try await ignoringNotFound {
            try await stop(id: id)
        }
        try await ignoringNotFound {
            try await delete(id: id)
        }
    }

    public static func isIgnorableError(_ error: Error) -> Bool {
        if let error = error as? ContainerizationError {
            if error.isCode(.notFound) {
                return true
            }
            if let cause = error.cause {
                return isIgnorableError(cause)
            }
            return false
        }
        if let aggregate = error as? AggregateError {
            return !aggregate.errors.isEmpty
                && aggregate.errors.allSatisfy { isIgnorableError($0) }
        }
        return false
    }

    private static func stop(id: String) async throws {
        let client = ContainerClient()
        try await client.stop(id: id)
    }

    private static func delete(id: String) async throws {
        let client = ContainerClient()
        try await client.delete(id: id, force: true)
    }

    private static func ignoringNotFound(_ body: () async throws -> Void) async throws {
        do {
            try await body()
        } catch {
            if !isIgnorableError(error) {
                throw error
            }
        }
    }
}
