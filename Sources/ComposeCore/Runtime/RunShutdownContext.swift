import Foundation

/// Graceful stop context for a single one-off `compose run` container.
package struct RunShutdownContext: Sendable {
    package let containerID: String
    package let options: GracefulStopOptions

    package init(containerID: String, options: GracefulStopOptions) {
        self.containerID = containerID
        self.options = options
    }

    package static func stopAndRemove(context: RunShutdownContext) async throws {
        try await ContainerTeardown.stopGracefully(id: context.containerID, options: context.options)
        try await ContainerTeardown.teardown(id: context.containerID)
    }
}
