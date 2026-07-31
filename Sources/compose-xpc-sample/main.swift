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

        if options.operation == "up" || options.operation == "scale" {
            guard !options.files.isEmpty else {
                fputs("error: --file is required for \(options.operation)\n", stderr)
                printUsage()
                exit(2)
            }
        }
        if options.operation == "scale" && options.scales.isEmpty {
            fputs("error: --scale SERVICE=COUNT is required for scale\n", stderr)
            printUsage()
            exit(2)
        }

        let requestJSON: String
        do {
            requestJSON = try ComposeXPCCodec.encode(
                ComposeXPCProjectRequest(
                    projectName: projectName,
                    files: options.files,
                    dryRun: options.dryRun,
                    scales: options.scales
                )
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
        var dryRun = false
        var projectName: String?
        var operation = "status"
        var files: [String] = []
        var scales: [String: Int] = [:]
    }

    private static func parseOptions() -> Options {
        var options = Options()
        var arguments = CommandLine.arguments.dropFirst()
        while let arg = arguments.first {
            arguments = arguments.dropFirst()
            applyArgument(arg, arguments: &arguments, options: &options)
        }
        return options
    }

    private static func applyArgument(
        _ arg: String,
        arguments: inout ArraySlice<String>,
        options: inout Options
    ) {
        if arg == "--mach" {
            options.useMach = true
            return
        }
        if arg == "--dry-run" {
            options.dryRun = true
            return
        }
        if arg == "--project" || arg == "-p" {
            options.projectName = arguments.first
            if options.projectName != nil { arguments = arguments.dropFirst() }
            return
        }
        if arg == "--file" || arg == "-f" {
            if let path = arguments.first {
                options.files.append(path)
                arguments = arguments.dropFirst()
            }
            return
        }
        if arg == "--scale" {
            if let entry = arguments.first {
                parseScaleEntry(entry, into: &options.scales)
                arguments = arguments.dropFirst()
            }
            return
        }
        if arg == "status" || arg == "ps" || arg == "up" || arg == "down" || arg == "scale" {
            options.operation = arg
            return
        }
        if arg == "--help" || arg == "-h" {
            printUsage()
            exit(0)
        }
        fputs("Unknown argument: \(arg)\n", stderr)
        printUsage()
        exit(2)
    }

    private static func parseScaleEntry(_ entry: String, into scales: inout [String: Int]) {
        guard let separator = entry.firstIndex(of: "=") else {
            fputs("error: invalid --scale '\(entry)' (use SERVICE=COUNT)\n", stderr)
            exit(2)
        }
        let service = String(entry[..<separator]).trimmingCharacters(in: .whitespaces)
        let countText = String(entry[entry.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
        guard let count = Int(countText), count >= 1, !service.isEmpty else {
            fputs("error: invalid --scale '\(entry)' (use SERVICE=COUNT)\n", stderr)
            exit(2)
        }
        scales[service] = count
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
        case "scale":
            proxy.scale(requestJSON: requestJSON, reply: reply)
        default:
            fputs("error: unsupported operation \(operation)\n", stderr)
            exit(2)
        }
    }

    private static func printUsage() {
        fputs(
            """
            usage: compose-xpc-sample [--mach] [--dry-run] --project NAME \\
              [--file PATH ...] [--scale SERVICE=COUNT ...] \\
              <status|ps|up|down|scale>

            """,
            stderr
        )
    }
}
