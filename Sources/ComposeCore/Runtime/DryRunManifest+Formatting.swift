import Foundation

package enum DryRunManifestFormatting {
    struct ParsedRunArguments: Sendable, Equatable {
        var ports: [String] = []
        var labels: [String: String] = [:]
        var volumes: [String] = []
        var env: [String] = []
        var detach = false
        var interactive = false
        var tty = false
        var remove = false
    }

    package static func formatBuild(
        service: String,
        tag: String,
        context: String,
        dockerfile: String?
    ) -> String {
        let dockerfilePart: String
        if let dockerfile, !dockerfile.isEmpty {
            dockerfilePart = " dockerfile=\"\(dockerfile)\""
        } else {
            dockerfilePart = ""
        }
        return """
        [DRY-RUN] build image \"\(tag)\" service=\"\(service)\" context=\"\(context)\"\(dockerfilePart)
        """
    }

    package static func formatCreate(_ plan: ServicePlan) -> String {
        var parsed = parseRunArguments(plan.runArguments)
        appendFileMountVolumes(from: plan.fileMounts, into: &parsed.volumes)
        let ports = formatStringArray(parsed.ports.sorted())
        let labels = formatLabelMap(parsed.labels)
        let volumes = formatStringArray(parsed.volumes.sorted())
        let env = formatStringArray(parsed.env.sorted())
        let flags = formatBooleanFlags(parsed)
        let header = "[DRY-RUN] create container \"\(plan.name)\" image=\(plan.image)"
        let details = "ports=\(ports) labels=\(labels) volumes=\(volumes) env=\(env)"
        return flags.isEmpty ? "\(header) \(details)" : "\(header) \(details) \(flags)"
    }

    package static func formatTeardown(_ name: String, reason: DryRunManifest.TeardownReason) -> String {
        switch reason {
        case .shutdown:
            return "[DRY-RUN] stop+delete container \"\(name)\""
        case .orphan:
            return "[DRY-RUN] stop+delete container \"\(name)\" reason=orphan"
        }
    }

    package static func formatHealthWait(_ gate: HealthGate) -> String {
        let condition = formatCondition(gate.condition)
        let containers = formatStringArray(gate.containerNames)
        return """
        [DRY-RUN] wait for service "\(gate.dependencyService)" condition=\(condition) containers=\(containers)
        """
    }

    package static func formatExec(container: String, command: [String]) -> String {
        "[DRY-RUN] exec container \"\(container)\" command=\(formatStringArray(command))"
    }

    package static func formatPurge(path: String) -> String {
        "[DRY-RUN] purge bind-mount path \"\(path)\""
    }

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

    private static func formatBooleanFlags(_ parsed: ParsedRunArguments) -> String {
        var flags: [String] = []
        if parsed.detach { flags.append("detach=true") }
        if parsed.interactive { flags.append("interactive=true") }
        if parsed.tty { flags.append("tty=true") }
        if parsed.remove { flags.append("remove=true") }
        return flags.joined(separator: " ")
    }

    private static func appendFileMountVolumes(
        from mounts: [PlannedFileMount],
        into volumes: inout [String]
    ) {
        for mount in mounts {
            let source = mount.sourceRelativePath
            volumes.append("\(source):\(mount.containerTarget):ro")
        }
    }

    private static func formatCondition(_ condition: DependsOnCondition) -> String {
        switch condition {
        case .orderingOnly:
            return "ordering_only"
        case .serviceStarted:
            return "service_started"
        case .serviceHealthy:
            return "service_healthy"
        }
    }

    private static func formatStringArray(_ values: [String]) -> String {
        let quoted = values.map { "\"\($0)\"" }
        return "[\(quoted.joined(separator: ", "))]"
    }

    private static func formatLabelMap(_ labels: [String: String]) -> String {
        guard !labels.isEmpty else { return "{}" }
        let pairs = labels.keys.sorted().map { key in
            "\"\(key)\": \"\(labels[key] ?? "")\""
        }
        return "{\(pairs.joined(separator: ", "))}"
    }
}
