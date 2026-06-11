import Foundation

enum ComposeDuration {
  static func parse(_ raw: String, field: String, allowZero: Bool = false) throws -> Duration {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw ComposeError.invalidField(field, reason: "expected a duration like 30s or 1m")
    }

    var totalNanoseconds: Int64 = 0
    var index = trimmed.startIndex

    while index < trimmed.endIndex {
      let segment = try parseSegment(in: trimmed, startingAt: &index, field: field, raw: raw)
      totalNanoseconds += segment
    }

    guard allowZero || totalNanoseconds > 0 else {
      throw ComposeError.invalidField(field, reason: "duration must be greater than zero")
    }
    return .nanoseconds(totalNanoseconds)
  }

  private static func parseSegment(
    in trimmed: String,
    startingAt index: inout String.Index,
    field: String,
    raw: String
  ) throws -> Int64 {
    let start = index
    while index < trimmed.endIndex, trimmed[index].isNumber || trimmed[index] == "." {
      index = trimmed.index(after: index)
    }
    guard start != index else {
      throw ComposeError.invalidField(field, reason: "invalid duration '\(raw)'")
    }

    let numberText = String(trimmed[start..<index])
    guard let value = Double(numberText) else {
      throw ComposeError.invalidField(field, reason: "invalid duration '\(raw)'")
    }

    guard index < trimmed.endIndex else {
      throw ComposeError.invalidField(field, reason: "missing unit in duration '\(raw)'")
    }

    var unitEnd = index
    while unitEnd < trimmed.endIndex, trimmed[unitEnd].isLetter {
      unitEnd = trimmed.index(after: unitEnd)
    }
    let unit = String(trimmed[index..<unitEnd])
    index = unitEnd

    return try nanoseconds(for: unit, value: value, field: field, raw: raw)
  }

  private static func nanoseconds(
    for unit: String,
    value: Double,
    field: String,
    raw: String
  ) throws -> Int64 {
    switch unit {
    case "ns":
      return Int64(value)
    case "us":
      return Int64(value * 1_000)
    case "ms":
      return Int64(value * 1_000_000)
    case "s":
      return Int64(value * 1_000_000_000)
    case "m":
      return Int64(value * 60 * 1_000_000_000)
    case "h":
      return Int64(value * 3_600 * 1_000_000_000)
    default:
      throw ComposeError.invalidField(field, reason: "unknown duration unit '\(unit)' in '\(raw)'")
    }
  }
}
