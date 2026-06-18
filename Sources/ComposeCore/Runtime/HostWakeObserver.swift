#if os(macOS)
@preconcurrency import AppKit
import Foundation

/// macOS host wake notifications as an `AsyncStream`.
package enum HostWakeObserver {
    package static func events() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let center = NSWorkspace.shared.notificationCenter
            let observer = center.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { _ in
                continuation.yield()
            }
            continuation.onTermination = { _ in
                center.removeObserver(observer)
            }
        }
    }
}
#endif
