import Foundation

public struct ComposeResourceLimits: Sendable, Equatable {
    public let cpus: String?
    public let memory: String?

    public init(cpus: String?, memory: String?) {
        self.cpus = cpus
        self.memory = memory
    }

    var hasContent: Bool {
        cpus != nil || memory != nil
    }
}

public struct ComposeResourceReservations: Sendable, Equatable {
    public let devices: [ComposeResourceReservationDevice]

    public init(devices: [ComposeResourceReservationDevice]) {
        self.devices = devices
    }

    var hasContent: Bool {
        !devices.isEmpty
    }
}

public struct ComposeResourceReservationDevice: Sendable, Equatable {
    public let driver: String
    public let capabilities: [String]

    public init(driver: String, capabilities: [String]) {
        self.driver = driver
        self.capabilities = capabilities
    }
}

public struct ComposeDeployResources: Sendable, Equatable {
    public let limits: ComposeResourceLimits?
    public let reservations: ComposeResourceReservations?

    public init(
        limits: ComposeResourceLimits?,
        reservations: ComposeResourceReservations? = nil
    ) {
        self.limits = limits
        self.reservations = reservations
    }

    var hasContent: Bool {
        limits?.hasContent == true || reservations?.hasContent == true
    }
}

extension ComposeResourceLimits: Codable {
    private enum CodingKeys: String, CodingKey {
        case cpus
        case memory
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cpus = try Self.decodeOptionalString(forKey: .cpus, from: container)
        memory = try Self.decodeOptionalString(forKey: .memory, from: container)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(cpus, forKey: .cpus)
        try container.encodeIfPresent(memory, forKey: .memory)
    }

    private static func decodeOptionalString(
        forKey key: CodingKeys,
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> String? {
        if let value = try container.decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try container.decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try container.decodeIfPresent(Double.self, forKey: key) {
            return String(value)
        }
        return nil
    }
}

extension ComposeDeployResources: Codable {
    private enum CodingKeys: String, CodingKey {
        case limits
        case reservations
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        limits = try container.decodeIfPresent(ComposeResourceLimits.self, forKey: .limits)
        reservations = try container.decodeIfPresent(ComposeResourceReservations.self, forKey: .reservations)
    }

    public func encode(to encoder: Encoder) throws {
        guard hasContent else { return }
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let limits, limits.hasContent {
            try container.encode(limits, forKey: .limits)
        }
        if let reservations, reservations.hasContent {
            try container.encode(reservations, forKey: .reservations)
        }
    }
}

extension ComposeResourceReservations: Codable {
    private enum CodingKeys: String, CodingKey {
        case devices
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        devices = try container.decodeIfPresent([ComposeResourceReservationDevice].self, forKey: .devices) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        guard hasContent else { return }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(devices, forKey: .devices)
    }
}

extension ComposeResourceReservationDevice: Codable {
    private enum CodingKeys: String, CodingKey {
        case driver
        case capabilities
    }

    // Parse-time: enforce supported schema (driver/capabilities). Plan-time runtime support is
    // checked separately in DeployGPUPlanning when up/run/config --quiet would start workloads.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawDriver = try container.decodeIfPresent(String.self, forKey: .driver) ?? ""
        let driver = rawDriver.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard driver == "apple" else {
            let rendered = rawDriver.isEmpty ? "<missing>" : rawDriver
            throw ComposeError.invalidField(
                "deploy.resources.reservations.devices.driver",
                reason: "unsupported driver '\(rendered)'; only 'apple' is supported"
            )
        }

        let rawCapabilities = try container.decodeIfPresent([String].self, forKey: .capabilities) ?? []
        guard !rawCapabilities.isEmpty else {
            throw ComposeError.invalidField(
                "deploy.resources.reservations.devices.capabilities",
                reason: "expected a non-empty list containing 'gpu'"
            )
        }

        let capabilities = rawCapabilities.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        guard capabilities.allSatisfy({ $0 == "gpu" }) else {
            let unsupported = Set(capabilities.filter { $0 != "gpu" }).sorted()
            throw ComposeError.invalidField(
                "deploy.resources.reservations.devices.capabilities",
                reason: "unsupported capabilities \(unsupported); only ['gpu'] is supported"
            )
        }

        self.driver = driver
        self.capabilities = capabilities
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(driver, forKey: .driver)
        try container.encode(capabilities, forKey: .capabilities)
    }
}
