import CoreServices
import Foundation

/// macOS FSEvents monitor for a single develop.watch rule.
package struct FileWatchMonitor: Sendable {
    package struct Event: Sendable {
        package let hostPath: URL
    }

    package let resolved: ResolvedWatchRule
    private let watchPath: String
    private let watchRootPath: String

    package init(resolved: ResolvedWatchRule) {
        self.resolved = resolved
        let root = resolved.watchRoot.standardizedFileURL.path
        self.watchRootPath = root
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: root, isDirectory: &isDirectory), !isDirectory.boolValue {
            self.watchPath = resolved.watchRoot.deletingLastPathComponent().path
        } else {
            self.watchPath = root
        }
    }

    package func events() -> AsyncStream<Event> {
        let resolved = resolved
        let watchPath = watchPath
        let watchRootPath = watchRootPath

        return AsyncStream { continuation in
            let queue = DispatchQueue(label: "compose.filewatch.\(resolved.ruleID)")
            let callbackState = CallbackState(
                watchRoot: resolved.watchRoot,
                watchRootPath: watchRootPath,
                ignore: resolved.rule.ignore,
                continuation: continuation
            )
            var context = FSEventStreamContext(
                version: 0,
                info: Unmanaged.passRetained(callbackState).toOpaque(),
                retain: nil,
                release: { pointer in
                    Unmanaged<CallbackState>.fromOpaque(pointer!).release()
                },
                copyDescription: nil
            )

            let pathsToWatch = [watchPath] as CFArray
            let flags = FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes
            )
            guard let stream = FSEventStreamCreate(
                kCFAllocatorDefault,
                fseventsCallback,
                &context,
                pathsToWatch,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                0.1,
                flags
            ) else {
                fputs("Error: couldn't start file watch for \(resolved.rule.path).\n", stderr)
                continuation.finish()
                return
            }

            FSEventStreamSetDispatchQueue(stream, queue)
            FSEventStreamStart(stream)
            let streamBox = StreamBox(stream: stream)

            continuation.onTermination = { _ in
                streamBox.stop()
            }
        }
    }

    package static func shouldEmit(
        path: String,
        watchRoot: URL,
        watchRootPath: String,
        ignore: [String]
    ) -> URL? {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let standardized = url.path
        if standardized != watchRootPath {
            let prefix = watchRootPath.hasSuffix("/") ? watchRootPath : watchRootPath + "/"
            guard standardized.hasPrefix(prefix) else { return nil }
        }
        guard let relative = WatchPathValidator.relativePath(from: watchRoot, to: url) else {
            return nil
        }
        if WatchPathValidator.isIgnored(relativePath: relative, patterns: ignore) {
            return nil
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized, isDirectory: &isDirectory) else {
            return nil
        }
        if isDirectory.boolValue {
            return nil
        }
        return url
    }
}

private final class StreamBox: @unchecked Sendable {
    private let stream: FSEventStreamRef

    init(stream: FSEventStreamRef) {
        self.stream = stream
    }

    func stop() {
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}

private final class CallbackState: @unchecked Sendable {
    let watchRoot: URL
    let watchRootPath: String
    let ignore: [String]
    let continuation: AsyncStream<FileWatchMonitor.Event>.Continuation

    init(
        watchRoot: URL,
        watchRootPath: String,
        ignore: [String],
        continuation: AsyncStream<FileWatchMonitor.Event>.Continuation
    ) {
        self.watchRoot = watchRoot
        self.watchRootPath = watchRootPath
        self.ignore = ignore
        self.continuation = continuation
    }

    func handle(path: String) {
        guard let url = FileWatchMonitor.shouldEmit(
            path: path,
            watchRoot: watchRoot,
            watchRootPath: watchRootPath,
            ignore: ignore
        ) else { return }
        continuation.yield(FileWatchMonitor.Event(hostPath: url))
    }
}

private func fseventsCallback( // swiftlint:disable:this function_parameter_count
    _: ConstFSEventStreamRef,
    clientInfo: UnsafeMutableRawPointer?,
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer,
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    _: UnsafePointer<FSEventStreamEventId>
) {
    guard let clientInfo else { return }
    let state = Unmanaged<CallbackState>.fromOpaque(clientInfo).takeUnretainedValue()
    let paths = unsafeBitCast(eventPaths, to: NSArray.self)
    for index in 0..<numEvents {
        if eventFlags[index] & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved) != 0 {
            continue
        }
        let path = paths[index] as? String
        guard let path else { continue }
        state.handle(path: path)
    }
}
