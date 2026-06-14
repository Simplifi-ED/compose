import Foundation

package enum ProjectEventFormat {
    private static let timestampStyle = Date.ISO8601FormatStyle(
        dateTimeSeparator: .standard,
        includingFractionalSeconds: true,
        timeZone: .gmt
    )

    package static func formatLine(transition: ProjectEventTransition, timestamp: Date) -> String {
        let stamp = timestamp.formatted(timestampStyle)
        return "[\(stamp)] container \(transition.kind.rawValue) \(transition.containerID) " +
            "(\(transition.containerName))\n"
    }

    package static func formatLine(event: ProjectEvent) -> String {
        formatLine(
            transition: ProjectEventTransition(
                kind: event.kind,
                containerID: event.containerID,
                containerName: event.containerName
            ),
            timestamp: event.timestamp
        )
    }
}
