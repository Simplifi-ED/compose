import ContainerAPIClient
import Foundation

package enum DeployResourceLimitsPlanning {
    package static let fractionalCPUReason =
        "Apple container hypervisor requires whole CPU cores. Fractional limits like '0.5' or '50m' "
        + "are not supported by the Virtualization.framework. Please change your limit to a whole "
        + "integer (e.g., '1', '2')."

    package static func validatedRunFlags(limits: ComposeResourceLimits?) throws -> [String] {
        guard let limits else { return [] }
        var flags: [String] = []
        if let cpus = limits.cpus {
            flags.append(contentsOf: ["--cpus", try validatedWholeCoreCount(cpus)])
        }
        if let memory = limits.memory {
            flags.append(contentsOf: ["--memory", try validatedMemoryString(memory)])
        }
        return flags
    }

    package static func validateLimits(_ limits: ComposeResourceLimits?) throws {
        _ = try validatedRunFlags(limits: limits)
    }

    private static func validatedWholeCoreCount(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            throw ComposeError.invalidField(
                "deploy.resources.limits.cpus",
                reason: "expected a positive whole number (got \(raw))"
            )
        }

        if isMillicoreNotation(trimmed) {
            throw ComposeError.invalidField(
                "deploy.resources.limits.cpus",
                reason: fractionalCPUReason
            )
        }

        if trimmed.contains(".") {
            guard let value = Double(trimmed), value.truncatingRemainder(dividingBy: 1) == 0, value > 0 else {
                throw ComposeError.invalidField(
                    "deploy.resources.limits.cpus",
                    reason: fractionalCPUReason
                )
            }
            return String(Int(value))
        }

        guard let value = Int(trimmed), value > 0 else {
            throw ComposeError.invalidField(
                "deploy.resources.limits.cpus",
                reason: "expected a positive whole number (got \(raw))"
            )
        }
        return String(value)
    }

    private static func isMillicoreNotation(_ value: String) -> Bool {
        let lower = value.lowercased()
        guard lower.hasSuffix("m"), lower.count > 1 else { return false }
        let digits = lower.dropLast()
        return !digits.isEmpty && digits.allSatisfy(\.isNumber)
    }

    private static func validatedMemoryString(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            throw ComposeError.invalidField(
                "deploy.resources.limits.memory",
                reason: "invalid size '\(raw)'"
            )
        }
        do {
            _ = try Parser.memoryStringAsMiB(trimmed)
        } catch {
            throw ComposeError.invalidField(
                "deploy.resources.limits.memory",
                reason: "invalid size '\(raw)'"
            )
        }
        return trimmed
    }
}
