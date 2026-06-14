import os.signpost

// ponytail: gate + signposter lookup; interval names live at call sites
package enum SignpostTelemetry {
    package enum Category: Sendable {
        case orchestration
        case networks
        case volumes
    }

    package static let parse: StaticString = "compose.parse"
    package static let plan: StaticString = "compose.plan"
    package static let executeWave: StaticString = "compose.execute.wave"
    package static let discovery: StaticString = "compose.discovery"
    package static let network: StaticString = "compose.network"
    package static let volume: StaticString = "compose.volume"

    package static func interval<T>(
        _ name: StaticString,
        category: Category = .orchestration,
        _ body: () throws -> T
    ) rethrows -> T {
        guard OsLogConfiguration.sessionEnabled else { return try body() }
        return try signposter(for: category).withIntervalSignpost(name, around: body)
    }

    package static func interval<T>(
        _ name: StaticString,
        category: Category = .orchestration,
        _ body: () async throws -> T
    ) async rethrows -> T {
        guard OsLogConfiguration.sessionEnabled else { return try await body() }
        // ponytail: no async withIntervalSignpost in this SDK; manual begin/end matches sync helper semantics
        let signposter = signposter(for: category)
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return try await body()
    }

    private static func signposter(for category: Category) -> OSSignposter {
        switch category {
        case .orchestration:
            OsLogConfiguration.orchestrationSignposter
        case .networks:
            OsLogConfiguration.networksSignposter
        case .volumes:
            OsLogConfiguration.volumesSignposter
        }
    }
}
