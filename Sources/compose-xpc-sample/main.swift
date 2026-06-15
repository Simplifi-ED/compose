import ComposeCore
import Foundation

@main
struct ComposeXPCSample {
    static func main() {
        let options = parseOptions()
        guard let projectName = options.projectName else {
            fputs("error: --project is required\n", stderr)
            printUsage()
            exit(2)
        }

        let requestJSON: String
        do {
            requestJSON = try ComposeXPCCodec.encode(
                ComposeXPCProjectRequest(projectName: projectName)
            )
        } catch {
            fputs("error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }

        do {
            let output = try invoke(operation: options.operation, requestJSON: requestJSON, useMach: options.useMach)
            print(output)
        } catch {
            fputs("error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private struct Options {
        var useMach = false
        var projectName: String?
        var operation = "status"
    }

    private static func parseOptions() -> Options {
        var options = Options()
        var arguments = CommandLine.arguments.dropFirst()
        while let arg = arguments.first {
            arguments = arguments.dropFirst()
            switch arg {
            case "--mach":
                options.useMach = true
            case "--project", "-p":
                options.projectName = arguments.first
                if options.projectName != nil { arguments = arguments.dropFirst() }
            case "status", "ps", "up", "down":
                options.operation = arg
            case "--help", "-h":
                printUsage()
                exit(0)
            default:
                fputs("Unknown argument: \(arg)\n", stderr)
                printUsage()
                exit(2)
            }
        }
        return options
    }

    private static func invoke(operation: String, requestJSON: String, useMach: Bool) throws -> String {
        let connection = try ComposeXPCConnectionFactory.makeClientConnection(useMachService: useMach)
        defer { connection.invalidate() }
        let semaphore = DispatchSemaphore(value: 0)
        var output: String?
        var replyError: NSError?
        let reply: (String?, NSError?) -> Void = { json, error in
            output = json
            replyError = error
            semaphore.signal()
        }

        let proxy = connection.remoteObjectProxyWithErrorHandler { error in
            replyError = error as NSError
            semaphore.signal()
        } as? ComposeXPCProtocol
        guard let proxy else {
            throw ComposeXPCError.invalidRequest("Could not create XPC proxy.")
        }
        connection.resume()
        dispatchOperation(operation, proxy: proxy, requestJSON: requestJSON, reply: reply)
        let waitResult = semaphore.wait(timeout: .now() + .seconds(30))
        if waitResult == .timedOut {
            throw ComposeXPCError.invalidRequest("Timed out waiting for XPC response.")
        }

        if let replyError {
            throw replyError
        }
        guard let output else {
            throw ComposeXPCError.invalidRequest("Empty XPC response.")
        }
        return output
    }

    private static func dispatchOperation(
        _ operation: String,
        proxy: ComposeXPCProtocol,
        requestJSON: String,
        reply: @escaping (String?, NSError?) -> Void
    ) {
        switch operation {
        case "status":
            proxy.status(requestJSON: requestJSON, reply: reply)
        case "ps":
            proxy.ps(requestJSON: requestJSON, reply: reply)
        case "up":
            proxy.up(requestJSON: requestJSON, reply: reply)
        case "down":
            proxy.down(requestJSON: requestJSON, reply: reply)
        default:
            fputs("error: unsupported operation \(operation)\n", stderr)
            exit(2)
        }
    }

    private static func printUsage() {
        fputs(
            """
            usage: compose-xpc-sample [--mach] --project NAME <status|ps|up|down>

            """,
            stderr
        )
    }
}
