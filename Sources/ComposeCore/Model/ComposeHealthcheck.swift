import Foundation

public enum ComposeHealthcheckTest: Sendable, Equatable {
  case cmd([String])
  case cmdShell(String)
}

public struct ComposeHealthcheck: Sendable, Equatable {
  public let test: ComposeHealthcheckTest
  public let interval: Duration
  public let timeout: Duration
  public let retries: Int
  public let startPeriod: Duration

  public init(
    test: ComposeHealthcheckTest,
    interval: Duration = .seconds(30),
    timeout: Duration = .seconds(5),
    retries: Int = 3,
    startPeriod: Duration = .zero
  ) {
    self.test = test
    self.interval = interval
    self.timeout = timeout
    self.retries = retries
    self.startPeriod = startPeriod
  }

}

extension ComposeHealthcheck: Decodable {
  private enum CodingKeys: String, CodingKey {
    case test
    case interval
    case timeout
    case retries
    case startPeriod = "start_period"
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    test = try Self.decodeTest(from: container)

    if let intervalText = try container.decodeIfPresent(String.self, forKey: .interval) {
      interval = try ComposeDuration.parse(intervalText, field: "healthcheck.interval")
    } else {
      interval = .seconds(30)
    }

    if let timeoutText = try container.decodeIfPresent(String.self, forKey: .timeout) {
      timeout = try ComposeDuration.parse(timeoutText, field: "healthcheck.timeout")
    } else {
      timeout = .seconds(5)
    }

    retries = try container.decodeIfPresent(Int.self, forKey: .retries) ?? 3
    guard retries >= 1 else {
      throw ComposeError.invalidField("healthcheck.retries", reason: "expected an integer of 1 or more")
    }

    if let startPeriodText = try container.decodeIfPresent(String.self, forKey: .startPeriod) {
      startPeriod = try ComposeDuration.parse(
        startPeriodText,
        field: "healthcheck.start_period",
        allowZero: true
      )
    } else {
      startPeriod = .zero
    }
  }

  private static func decodeTest(
    from container: KeyedDecodingContainer<CodingKeys>
  ) throws -> ComposeHealthcheckTest {
    guard container.contains(.test) else {
      throw ComposeError.invalidField("healthcheck", reason: "expected a test command")
    }

    if let command = try? container.decode(String.self, forKey: .test) {
      return try decodeStringTest(command)
    }

    if let values = try? container.decode([String].self, forKey: .test) {
      return try decodeListTest(values)
    }

    throw ComposeError.invalidField("healthcheck.test", reason: "expected a string or list of strings")
  }

  private static func decodeStringTest(_ command: String) throws -> ComposeHealthcheckTest {
    let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.uppercased() == "NONE" {
      throw ComposeError.invalidField("healthcheck.test", reason: "NONE is not supported")
    }
    if trimmed.uppercased().hasPrefix("CMD-SHELL ") {
      let script = String(trimmed.dropFirst("CMD-SHELL ".count))
      guard !script.isEmpty else {
        throw ComposeError.invalidField("healthcheck.test", reason: "CMD-SHELL requires a command")
      }
      return .cmdShell(script)
    }
    if trimmed.uppercased().hasPrefix("CMD ") {
      let payload = String(trimmed.dropFirst("CMD ".count))
      let parts = payload.split(whereSeparator: \.isWhitespace).map(String.init)
      guard !parts.isEmpty else {
        throw ComposeError.invalidField("healthcheck.test", reason: "CMD requires a command")
      }
      return .cmd(parts)
    }
    let parts = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
    guard !parts.isEmpty else {
      throw ComposeError.invalidField("healthcheck.test", reason: "expected a command")
    }
    return .cmd(parts)
  }

  private static func decodeListTest(_ values: [String]) throws -> ComposeHealthcheckTest {
    guard let head = values.first else {
      throw ComposeError.invalidField("healthcheck.test", reason: "expected a command")
    }
    switch head.uppercased() {
    case "NONE":
      throw ComposeError.invalidField("healthcheck.test", reason: "NONE is not supported")
    case "CMD":
      let command = Array(values.dropFirst())
      guard !command.isEmpty else {
        throw ComposeError.invalidField("healthcheck.test", reason: "CMD requires a command")
      }
      return .cmd(command)
    case "CMD-SHELL":
      guard values.count == 2, !values[1].isEmpty else {
        throw ComposeError.invalidField("healthcheck.test", reason: "CMD-SHELL requires a shell command")
      }
      return .cmdShell(values[1])
    default:
      return .cmd(values)
    }
  }
}
