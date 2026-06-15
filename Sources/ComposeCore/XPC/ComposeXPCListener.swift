import Foundation

package enum ComposeXPCListenerMode: Sendable {
    case machService
}

package final class ComposeXPCListenerController: NSObject, NSXPCListenerDelegate {
    private let listener: NSXPCListener

    package init(mode: ComposeXPCListenerMode = .machService) {
        listener = NSXPCListener(machServiceName: ComposeXPCConstants.machServiceName)
        super.init()
        listener.delegate = self
    }

    package func start() {
        listener.resume()
    }

    package func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        do {
            try ComposeXPCClientAuth.validate(connection: newConnection)
        } catch {
            return false
        }
        let service = ComposeXPCService()
        let interface = NSXPCInterface(with: ComposeXPCProtocol.self)
        newConnection.exportedInterface = interface
        newConnection.exportedObject = service
        newConnection.invalidationHandler = { service.cancelAll() }
        newConnection.interruptionHandler = { service.cancelAll() }
        newConnection.resume()
        return true
    }
}

package enum ComposeXPCConnectionFactory {
    package static func makeClientConnection(useMachService: Bool = true) throws -> NSXPCConnection {
        guard useMachService else {
            throw ComposeXPCError.invalidRequest(
                "XPC clients must use the Mach service. Run `compose xpc serve` or `compose xpc install` first."
            )
        }
        let connection = NSXPCConnection(machServiceName: ComposeXPCConstants.machServiceName)
        configure(connection)
        return connection
    }

    private static func configure(_ connection: NSXPCConnection) {
        connection.remoteObjectInterface = NSXPCInterface(with: ComposeXPCProtocol.self)
        connection.invalidationHandler = {}
        connection.interruptionHandler = {}
    }
}
