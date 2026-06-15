import Foundation

extension DryRunManifestFormatting {
    static func parseRunArguments(_ arguments: [String]) -> ParsedRunArguments {
        var parsed = ParsedRunArguments()
        var index = 0
        while index < arguments.count {
            let skip = applyRunFlag(
                arguments[index],
                arguments: arguments,
                at: index,
                into: &parsed
            )
            index += 1 + skip
        }
        return parsed
    }

    private static func applyRunFlag(
        _ flag: String,
        arguments: [String],
        at index: Int,
        into parsed: inout ParsedRunArguments
    ) -> Int {
        if let skip = applyValueRunFlag(flag, arguments: arguments, at: index, into: &parsed) {
            return skip
        }
        applyBooleanRunFlag(flag, into: &parsed)
        return 0
    }

    private static func applyValueRunFlag(
        _ flag: String,
        arguments: [String],
        at index: Int,
        into parsed: inout ParsedRunArguments
    ) -> Int? {
        let valueIndex = index + 1
        guard valueIndex < arguments.count else { return nil }
        let value = arguments[valueIndex]
        switch flag {
        case "-p":
            parsed.ports.append(value)
        case "-l":
            parseLabelArgument(value, into: &parsed.labels)
        case "-v":
            parsed.volumes.append(value)
        case "-e":
            parsed.env.append(value)
        case "--network":
            parsed.networks.append(value)
        case "--cpus", "-c":
            parsed.cpu = value
        case "--memory", "-m":
            parsed.memory = value
        case "--platform":
            parsed.platform = value
        default:
            return nil
        }
        return 1
    }

    private static func applyBooleanRunFlag(_ flag: String, into parsed: inout ParsedRunArguments) {
        switch flag {
        case "-d":
            parsed.detach = true
        case "-i":
            parsed.interactive = true
        case "-t":
            parsed.tty = true
        case "--rm":
            parsed.remove = true
        case "--init":
            parsed.useInit = true
        default:
            break
        }
    }

    private static func parseLabelArgument(_ label: String, into labels: inout [String: String]) {
        guard let separator = label.firstIndex(of: "=") else { return }
        let key = String(label[..<separator])
        let value = String(label[label.index(after: separator)...])
        labels[key] = value
    }

    static func formatBooleanFlags(_ parsed: ParsedRunArguments) -> String {
        var flags: [String] = []
        if parsed.detach { flags.append("detach=true") }
        if parsed.interactive { flags.append("interactive=true") }
        if parsed.tty { flags.append("tty=true") }
        if parsed.remove { flags.append("remove=true") }
        if parsed.useInit { flags.append("init=true") }
        return flags.joined(separator: " ")
    }

    static func appendFileMountVolumes(
        from mounts: [PlannedFileMount],
        into volumes: inout [String]
    ) {
        for mount in mounts {
            let source = mount.sourceRelativePath
            volumes.append(
                ComposeBindingKeys.VolumeSpec.readOnlyMount(
                    resolvedHostPath: source,
                    containerPath: mount.containerTarget
                )
            )
        }
    }
}
