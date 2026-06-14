import ArgumentParser
import Foundation

public struct Doctor: AsyncParsableCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        abstract: "Run pre-flight checks for container and compose plugin readiness."
    )

    @Flag(
        name: .long,
        help: "Exit with status code only; no report output."
    )
    var quiet = false

    public func run() async throws {
        let findings = await DoctorChecks.run()
        if !quiet {
            let mode = TerminalMode.resolve()
            for line in DoctorReport.lines(for: findings, mode: mode) {
                print(line)
            }
        }
        if DoctorReport.hasCriticalFailure(findings) {
            throw ExitCode(1)
        }
    }
}
