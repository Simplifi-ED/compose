import ContainerAPIClient
import ContainerResource
import Foundation
import MachineAPIClient

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

  static func statusProvider(machineContext: MachineContext) -> HealthWait.StatusProvider {
    { id in
      do {
        return try await ComposeContainerGateway.get(id: id, machineContext: machineContext).status
      } catch {
        if ContainerTeardown.isIgnorableError(error) {
          return nil
        }
        throw error
      }
    }
  }

  static func processRunner(machineContext: MachineContext) -> HealthWait.ProcessRunner {
    { containerName, configuration, timeout in
      if machineContext.isMachineMode {
        let snapshot = try machineContext.requireSnapshot()
        let execArgs = ["exec", containerName, configuration.executable] + configuration.arguments
        return try await runMachineHealthExec(
          snapshot: snapshot,
          arguments: execArgs,
          timeout: timeout
        )
      }
      let process = try await ComposeContainerGateway.createProcess(
        containerId: containerName,
        processId: UUID().uuidString.lowercased(),
        configuration: configuration,
        stdio: [nil, nil, nil],
        machineContext: machineContext
      )
      try await process.start()
      return try await waitForExit(process: process, timeout: timeout)
    }
  }

  private static func runMachineHealthExec(
    snapshot: MachineSnapshot,
    arguments: [String],
    timeout: Duration
  ) async throws -> Int32 {
    try await withThrowingTaskGroup(of: Int32.self) { group in
      group.addTask {
        let result = try await MachineInVMRunner.runCapturing(
          snapshot: snapshot,
          containerArguments: arguments
        )
        return result.exitCode
      }
      group.addTask {
        try await Task.sleep(for: timeout)
        throw TimedOut()
      }
      guard let exitCode = try await group.next() else {
        throw TimedOut()
      }
      group.cancelAll()
      return exitCode
    }
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
