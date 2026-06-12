import ArgumentParser
import Foundation

public struct MachineOptions: ParsableArguments {
    public init() {}

    @Option(
        name: .long,
        help: "Run against an existing container machine (see `container machine list`)."
    )
    var machine: String?

    var resolvedMachineName: String? {
        guard let machine else { return nil }
        let trimmed = machine.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public func validateMachineName() throws {
        guard machine != nil else { return }
        guard let name = resolvedMachineName else {
            throw ComposeError.invalidMachineName("")
        }
        try MachineNameValidator.validate(name)
    }

    package func rejectIfUnsupported(commandName: String) throws {
        guard machine != nil else { return }
        try validateMachineName()
        throw ComposeError.machineUnsupportedCommand(commandName)
    }

    package func resolveContext(
        stopped stoppedPolicy: MachineStoppedPolicy = .allowStopped
    ) async throws -> MachineContextResolution {
        try validateMachineName()
        let machineContext = try await MachineContext.resolve(
            machineName: resolvedMachineName
        )
        machineContext.printExecutionBanner()
        return try MachineContext.applyStoppedPolicy(machineContext, policy: stoppedPolicy)
    }
}

enum MachineNameValidator {
    private static let pattern = #"^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$"#

    static func validate(_ name: String) throws {
        guard !name.isEmpty else {
            throw ComposeError.invalidMachineName(name)
        }
        guard name.range(of: Self.pattern, options: .regularExpression) != nil else {
            throw ComposeError.invalidMachineName(name)
        }
    }
}
