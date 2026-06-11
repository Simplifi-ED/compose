import ContainerAPIClient
import ContainerResource
import Foundation

enum HealthProbe {
    static func processConfiguration(for test: ComposeHealthcheckTest) -> ProcessConfiguration {
        switch test {
        case .cmd(let arguments):
            guard let executable = arguments.first else {
                return ProcessConfiguration(
                    executable: "/bin/true",
                    arguments: [],
                    environment: [],
                    workingDirectory: "/",
                    terminal: false,
                    user: .raw(userString: "0:0"),
                    supplementalGroups: [],
                    rlimits: []
                )
            }
            return ProcessConfiguration(
                executable: executable,
                arguments: Array(arguments.dropFirst()),
                environment: [],
                workingDirectory: "/",
                terminal: false,
                user: .raw(userString: "0:0"),
                supplementalGroups: [],
                rlimits: []
            )
        case .cmdShell(let script):
            return ProcessConfiguration(
                executable: "/bin/sh",
                arguments: ["-c", script],
                environment: [],
                workingDirectory: "/",
                terminal: false,
                user: .raw(userString: "0:0"),
                supplementalGroups: [],
                rlimits: []
            )
        }
    }

    static func withTimeout(
        _ timeout: Duration,
        operation: @escaping @Sendable () async throws -> Int32
    ) async throws -> Int32 {
        try await withThrowingTaskGroup(of: Int32.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw CancellationError()
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    static func defaultStatus(id: String) async throws -> RuntimeStatus? {
        let client = ContainerClient()
        do {
            return try await client.get(id: id).status
        } catch {
            if ContainerTeardown.isIgnorableError(error) {
                return nil
            }
            throw error
        }
    }

    static func defaultProcessRunner(
        containerName: String,
        configuration: ProcessConfiguration
    ) async throws -> Int32 {
        let client = ContainerClient()
        let process = try await client.createProcess(
            containerId: containerName,
            processId: UUID().uuidString.lowercased(),
            configuration: configuration,
            stdio: [nil, nil, nil]
        )
        try await process.start()
        return try await process.wait()
    }
}
