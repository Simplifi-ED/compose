import Foundation

private final class ComposeXPCInFlightRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var tasks = [UUID: Task<Void, Never>]()

    func store(_ id: UUID, _ task: Task<Void, Never>) {
        lock.lock()
        tasks[id] = task
        lock.unlock()
    }

    func remove(_ id: UUID) {
        lock.lock()
        tasks.removeValue(forKey: id)
        lock.unlock()
    }

    func cancelAll() {
        lock.lock()
        let active = Array(tasks.values)
        tasks.removeAll()
        lock.unlock()
        active.forEach { $0.cancel() }
    }
}

private final class ComposeXPCReplyBox: @unchecked Sendable {
    let reply: (String?, NSError?) -> Void

    init(_ reply: @escaping (String?, NSError?) -> Void) {
        self.reply = reply
    }
}

package final class ComposeXPCService: NSObject, ComposeXPCProtocol {
    private let inFlight = ComposeXPCInFlightRegistry()

    package override init() {
        super.init()
    }

    package func cancelAll() {
        inFlight.cancelAll()
    }

    package func status(requestJSON: String, reply: @escaping (String?, NSError?) -> Void) {
        runAsync(requestJSON: requestJSON, reply: reply) {
            try await ComposeXPCHandlers.statusJSON(requestJSON)
        }
    }

    package func ps(requestJSON: String, reply: @escaping (String?, NSError?) -> Void) {
        status(requestJSON: requestJSON, reply: reply)
    }

    package func up(requestJSON: String, reply: @escaping (String?, NSError?) -> Void) {
        runAsync(requestJSON: requestJSON, reply: reply) {
            try await ComposeXPCHandlers.mutationJSON(requestJSON, operation: .startup)
        }
    }

    package func down(requestJSON: String, reply: @escaping (String?, NSError?) -> Void) {
        runAsync(requestJSON: requestJSON, reply: reply) {
            try await ComposeXPCHandlers.mutationJSON(requestJSON, operation: .shutdown)
        }
    }

    package func scale(requestJSON: String, reply: @escaping (String?, NSError?) -> Void) {
        runAsync(requestJSON: requestJSON, reply: reply) {
            try await ComposeXPCHandlers.scaleJSON(requestJSON)
        }
    }

    private func runAsync(
        requestJSON: String,
        reply: @escaping (String?, NSError?) -> Void,
        operation: @escaping @Sendable () async throws -> String
    ) {
        let box = ComposeXPCReplyBox(reply)
        let registry = inFlight
        let taskID = UUID()
        let task = Task {
            defer { registry.remove(taskID) }
            do {
                try Task.checkCancellation()
                let payload = try await operation()
                try Task.checkCancellation()
                box.reply(payload, nil)
            } catch is CancellationError {
                return
            } catch let error as NSError {
                box.reply(ComposeXPCCodec.errorResponseJSON(from: error), nil)
            } catch {
                let nsError = ComposeXPCError.nsError(
                    code: .operationFailed,
                    message: error.localizedDescription
                )
                box.reply(ComposeXPCCodec.errorResponseJSON(from: nsError), nil)
            }
        }
        registry.store(taskID, task)
    }
}
