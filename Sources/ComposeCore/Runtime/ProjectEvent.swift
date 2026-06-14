import Foundation

package enum ProjectEventKind: String, Sendable, Equatable {
    case start
    case die
}

/// A lifecycle transition detected by the foreground polling diff engine.
package struct ProjectEventTransition: Sendable, Equatable {
    package let kind: ProjectEventKind
    package let containerID: String
    package let containerName: String

    package init(kind: ProjectEventKind, containerID: String, containerName: String) {
        self.kind = kind
        self.containerID = containerID
        self.containerName = containerName
    }
}

/// Reserved for a future native engine event stream (`ComposeContainerGateway.events`).
package struct ProjectEvent: Sendable, Equatable {
    package let kind: ProjectEventKind
    package let containerID: String
    package let containerName: String
    package let timestamp: Date

    package init(
        kind: ProjectEventKind,
        containerID: String,
        containerName: String,
        timestamp: Date
    ) {
        self.kind = kind
        self.containerID = containerID
        self.containerName = containerName
        self.timestamp = timestamp
    }
}
