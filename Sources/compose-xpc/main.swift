import ComposeCore
import Foundation

@main
struct ComposeXPCEntry {
    static func main() {
        guard CommandLine.arguments.contains("--mach") else {
            fputs("compose-xpc: run under launchd with --mach (see compose xpc serve)\n", stderr)
            exit(2)
        }
        let controller = ComposeXPCListenerController()
        controller.start()
        fputs("compose-xpc Mach service \(ComposeXPCConstants.machServiceName)\n", stderr)
        dispatchMain()
    }
}
