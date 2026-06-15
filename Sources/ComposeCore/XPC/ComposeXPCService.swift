import Foundation

private final class ComposeXPCReplyBox: @unchecked Sendable {
    let reply: (String?, NSError?) -> Void

    init(_ reply: @escaping (String?, NSError?) -> Void) {
        self.reply = reply
    }
}

package final class ComposeXPCService: NSObject, ComposeXPCProtocol {
    package override init() {
        super.init()
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

    private func runAsync(
        requestJSON: String,
        reply: @escaping (String?, NSError?) -> Void,
        operation: @escaping @Sendable () async throws -> String
    ) {
        let box = ComposeXPCReplyBox(reply)
        Task {
            do {
                let payload = try await operation()
                box.reply(payload, nil)
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
    }
}
