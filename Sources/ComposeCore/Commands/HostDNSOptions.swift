import ArgumentParser
import Foundation

public struct HostDNSOptions: ParsableArguments {
    public init() {}

    @Flag(
        name: .long,
        help: """
        Install macOS host mappings for x-compose.hosts \
        (prompts for /etc/hosts access; compose stays unprivileged).
        """
    )
    public var hostDNS = false

    public var isEnabled: Bool { hostDNS }
}

extension HostDNSOptions {
    package func validateMachineCompatibility(machineName: String?) throws {
        guard isEnabled, machineName != nil else { return }
        throw ComposeError.hostDNSUnsupportedWithMachine
    }
}
