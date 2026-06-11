import Foundation

extension ComposeHealthcheck: Encodable {
    private enum CodingKeys: String, CodingKey {
        case test
        case interval
        case timeout
        case retries
        case startPeriod = "start_period"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try encodeTest(to: &container)

        if shouldExportInterval {
            try container.encode(
                ComposeDuration.composeString(from: interval),
                forKey: .interval
            )
        }
        if shouldExportTimeout {
            try container.encode(
                ComposeDuration.composeString(from: timeout),
                forKey: .timeout
            )
        }
        if shouldExportRetries {
            try container.encode(retries, forKey: .retries)
        }
        if shouldExportStartPeriod {
            try container.encode(
                ComposeDuration.composeString(from: startPeriod),
                forKey: .startPeriod
            )
        }
    }

    private var shouldExportInterval: Bool {
        exportPresence?.interval == true
            || (exportPresence == nil && interval != Self.defaultInterval)
    }

    private var shouldExportTimeout: Bool {
        exportPresence?.timeout == true
            || (exportPresence == nil && timeout != Self.defaultTimeout)
    }

    private var shouldExportRetries: Bool {
        exportPresence?.retries == true
            || (exportPresence == nil && retries != Self.defaultRetries)
    }

    private var shouldExportStartPeriod: Bool {
        exportPresence?.startPeriod == true
            || (exportPresence == nil && startPeriod != Self.defaultStartPeriod)
    }

    private func encodeTest(to container: inout KeyedEncodingContainer<CodingKeys>) throws {
        switch test {
        case .cmd(let command):
            try container.encode(["CMD"] + command, forKey: .test)
        case .cmdShell(let script):
            try container.encode(["CMD-SHELL", script], forKey: .test)
        }
    }
}
