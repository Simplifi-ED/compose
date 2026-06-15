import Foundation

package enum PlatformPlanning {
    package static let nativePlatform = "linux/arm64"
    package static let amd64Platform = "linux/amd64"

    package static let unsupportedPlatformReason =
        "only linux/arm64, linux/amd64, and linux/x86_64 are supported"
    package static let amd64RequiresAppleSiliconReason =
        "platform linux/amd64 requires Apple Silicon"
    package static let rosettaMissingReason =
        "Rosetta 2 isn't installed. Run compose doctor, or install with softwareupdate --install-rosetta"
    package static let machineUnsupportedReason =
        "platform isn't supported with --machine"

    package static func normalize(_ raw: String, serviceName: String? = nil) throws -> String {
        let field = serviceName.map { "services.\($0).platform" } ?? "platform"
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ComposeError.invalidField(field, reason: unsupportedPlatformReason)
        }
        let lower = trimmed.lowercased()
        switch lower {
        case "linux/amd64", "linux/x86_64":
            return amd64Platform
        case "linux/arm64":
            return nativePlatform
        default:
            throw ComposeError.invalidField(field, reason: unsupportedPlatformReason)
        }
    }

    package static func validate(
        services: [String: ComposeService],
        activeServiceNames: Set<String>,
        machineName: String?,
        hostMachine: String = RosettaAvailability.hostMachine(),
        rosettaInstalled: () -> Bool = RosettaAvailability.isInstalled
    ) throws {
        for serviceName in activeServiceNames.sorted() {
            guard let service = services[serviceName], let platform = service.platform else { continue }
            let normalized = try normalize(platform, serviceName: serviceName)
            if machineName != nil {
                throw ComposeError.invalidField(
                    "services.\(serviceName).platform",
                    reason: machineUnsupportedReason
                )
            }
            if normalized == amd64Platform {
                guard hostMachine == "arm64" else {
                    throw ComposeError.invalidField(
                        "services.\(serviceName).platform",
                        reason: amd64RequiresAppleSiliconReason
                    )
                }
                guard rosettaInstalled() else {
                    throw ComposeError.invalidField(
                        "services.\(serviceName).platform",
                        reason: rosettaMissingReason
                    )
                }
            }
        }
    }

    package static func validatedRunFlags(
        platform: String?,
        hostMachine: String = RosettaAvailability.hostMachine()
    ) throws -> [String] {
        guard let platform else { return [] }
        let normalized = try normalize(platform)
        if normalized == nativePlatform, hostMachine == "arm64" {
            return []
        }
        return ["--platform", normalized]
    }

    package static func warnBuildPlatformMismatch(serviceName: String, platform: String?) {
        guard let platform,
            (try? normalize(platform)) == amd64Platform
        else { return }
        fputs(
            "warning: service '\(serviceName)': platform linux/amd64 applies to container run; "
                + "image build still targets native arm64.\n",
            stderr
        )
    }
}

package enum RosettaAvailability {
    package static let installPath = "/Library/Apple/usr/share/rosetta/rosettad"

    package static func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: installPath)
    }

    package static func hostMachine() -> String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        let bytes = machine.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(bytes: bytes, encoding: .utf8) ?? "unknown"
    }
}
