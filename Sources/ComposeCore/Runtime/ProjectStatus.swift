import ContainerResource
import Foundation

public struct ProjectStatusRow: Sendable, Equatable {
    public let name: String
    public let service: String
    public let state: String
    public let ipAddress: String
    public let ports: String

    public var cells: [String] { [name, service, state, ipAddress, ports] }

    public init(name: String, service: String, state: String, ipAddress: String, ports: String) {
        self.name = name
        self.service = service
        self.state = state
        self.ipAddress = ipAddress
        self.ports = ports
    }
}

public enum ProjectStatus {
    public static func filteredContainers(
        from containers: [ProjectContainer],
        filter: Set<String>?
    ) -> [ProjectContainer] {
        guard let filter else {
            return containers
        }
        return containers.filter { container in
            guard let serviceName = container.serviceName else { return false }
            return filter.contains(serviceName)
        }
    }

    package static func filteredDiscoveredContainers(
        from containers: [DiscoveredContainer],
        filter: Set<String>?
    ) -> [DiscoveredContainer] {
        guard let filter else {
            return containers
        }
        return containers.filter { container in
            guard let serviceName = container.serviceName else { return false }
            return filter.contains(serviceName)
        }
    }

    public static func rows(
        from containers: [ProjectContainer],
        filter: Set<String>?,
        projectName: String? = nil,
        composeFile: ComposeFile? = nil
    ) -> [ProjectStatusRow] {
        let filtered = filteredContainers(from: containers, filter: filter)

        return filtered.map { container in
            ProjectStatusRow(
                name: container.name,
                service: container.serviceName ?? "",
                state: formatState(container.status),
                ipAddress: formatIP(
                    container: container,
                    projectName: projectName,
                    composeFile: composeFile
                ),
                ports: formatPorts(container.publishedPorts)
            )
        }
    }

    public static func formatState(_ status: RuntimeStatus) -> String {
        status.rawValue
    }

    public static func formatIP(
        container: ProjectContainer,
        projectName: String?,
        composeFile: ComposeFile?
    ) -> String {
        guard container.status == .running else { return "" }
        if let projectName, let composeFile,
           let address = ContainerNetworkDiscovery.primaryIPv4HostAddress(
               for: container,
               projectName: projectName,
               composeFile: composeFile
           ) {
            return address
        }
        return ContainerNetworkDiscovery.primaryIPv4HostAddress(from: container.networkAttachments) ?? ""
    }

    public static func formatPorts(_ ports: [PublishPort]) -> String {
        ports.flatMap(portDescriptions).joined(separator: ", ")
    }

    package static func defaultTable() -> TableFormat {
        TableFormat(columns: [
            TableFormat.Column(title: "NAME", width: 24),
            TableFormat.Column(title: "SERVICE", width: 12),
            TableFormat.Column(title: "STATE", width: 10, alignment: .right),
            TableFormat.Column(title: "IP", width: 18),
            TableFormat.Column(title: "PORTS", width: 32)
        ])
    }

    private static let portNumberStyle = IntegerFormatStyle<UInt>().grouping(.never)

    private static func portDescriptions(for port: PublishPort) -> [String] {
        (0..<Int(port.count)).map { offset in
            let hostPort = UInt(port.hostPort) + UInt(offset)
            let containerPort = UInt(port.containerPort) + UInt(offset)
            return "\(port.hostAddress.description):\(hostPort.formatted(portNumberStyle))"
                + "->\(containerPort.formatted(portNumberStyle))/\(port.proto.rawValue)"
        }
    }
}
