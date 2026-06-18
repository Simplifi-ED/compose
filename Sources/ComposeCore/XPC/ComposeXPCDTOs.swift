import Foundation

package struct ComposeXPCProjectRequest: Codable, Sendable, Equatable {
    package var projectName: String?
    package var files: [String]
    package var profiles: [String]
    package var services: [String]
    package var machineName: String?
    package var dryRun: Bool
    package var removeVolumes: Bool
    package var removeOrphans: Bool

    package init(
        projectName: String? = nil,
        files: [String] = [],
        profiles: [String] = [],
        services: [String] = [],
        machineName: String? = nil,
        dryRun: Bool = false,
        removeVolumes: Bool = false,
        removeOrphans: Bool = false
    ) {
        self.projectName = projectName
        self.files = files
        self.profiles = profiles
        self.services = services
        self.machineName = machineName
        self.dryRun = dryRun
        self.removeVolumes = removeVolumes
        self.removeOrphans = removeOrphans
    }
}

package struct ComposeXPCContainerRow: Codable, Sendable, Equatable {
    package let name: String
    package let service: String
    package let state: String
    package let ports: String
    package let ipAddress: String?

    package init(
        name: String,
        service: String,
        state: String,
        ports: String,
        ipAddress: String? = nil
    ) {
        self.name = name
        self.service = service
        self.state = state
        self.ports = ports
        self.ipAddress = ipAddress
    }
}

package struct ComposeXPCStatusResponse: Codable, Sendable, Equatable {
    package let exitStatus: Int
    package let containers: [ComposeXPCContainerRow]
    package let warnings: [String]

    package init(exitStatus: Int, containers: [ComposeXPCContainerRow], warnings: [String] = []) {
        self.exitStatus = exitStatus
        self.containers = containers
        self.warnings = warnings
    }
}

package struct ComposeXPCMutationResponse: Codable, Sendable, Equatable {
    package let exitStatus: Int
    package let affectedContainers: [String]
    package let warnings: [String]

    package init(exitStatus: Int, affectedContainers: [String], warnings: [String] = []) {
        self.exitStatus = exitStatus
        self.affectedContainers = affectedContainers
        self.warnings = warnings
    }
}

package struct ComposeXPCErrorResponse: Codable, Sendable, Equatable {
    package let code: Int
    package let message: String
}

package struct ComposeXPCAllowlistClient: Codable, Sendable, Equatable {
    package var teamID: String
    package var bundleID: String

    package init(teamID: String, bundleID: String) {
        self.teamID = teamID
        self.bundleID = bundleID
    }
}

package struct ComposeXPCAllowlist: Codable, Sendable, Equatable {
    package var teamIDs: [String]
    package var clients: [ComposeXPCAllowlistClient]
    /// When true, any validly signed client is admitted if teamIDs and clients are empty.
    package var allowAnySigned: Bool

    package init(
        teamIDs: [String] = [],
        clients: [ComposeXPCAllowlistClient] = [],
        allowAnySigned: Bool = false
    ) {
        self.teamIDs = teamIDs
        self.clients = clients
        self.allowAnySigned = allowAnySigned
    }
}
