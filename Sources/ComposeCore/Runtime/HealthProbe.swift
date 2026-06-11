import ContainerAPIClient
import ContainerResource
import Foundation

enum HealthProbe {
  struct TimedOut: Error {}

  static func processConfiguration(for test: ComposeHealthcheckTest) -> ProcessConfiguration {
    let base = ProcessConfiguration(
      executable: "/bin/true",
      arguments: [],
      environment: [],
      workingDirectory: "/",
      terminal: false,
      user: .raw(userString: "0:0"),
      supplementalGroups: [],
      rlimits: []
    )

    switch test {
    case .cmd(let arguments):
      guard let executable = arguments.first else {
        return base
      }
      var config = base
      config.executable = executable
      config.arguments = Array(arguments.dropFirst())
      return config
    case .cmdShell(let script):
      var config = base
      config.executable = "/bin/sh"
      config.arguments = ["-c", script]
      return config
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
    configuration: ProcessConfiguration,
    timeout: Duration
  ) async throws -> Int32 {
    let client = ContainerClient()
    let process = try await client.createProcess(
      containerId: containerName,
      processId: UUID().uuidString.lowercased(),
      configuration: configuration,
      stdio: [nil, nil, nil]
    )
    try await process.start()
    return try await waitForExit(process: process, timeout: timeout)
  }

  static func waitForExit(process: any ClientProcess, timeout: Duration) async throws -> Int32 {
    try await withThrowingTaskGroup(of: Int32.self) { group in
      group.addTask {
        try await process.wait()
      }
      group.addTask {
        try await Task.sleep(for: timeout)
        try? await process.kill(9)
        throw TimedOut()
      }
      guard let result = try await group.next() else {
        throw TimedOut()
      }
      group.cancelAll()
      return result
    }
  }
}
