import Foundation

package enum DotEnv {
    private static let keyPattern = #"^[A-Za-z_][A-Za-z0-9_]*$"#
    private static let placeholderRegex = try! NSRegularExpression(
        pattern: #"\$\{([A-Za-z_][A-Za-z0-9_]*)\}"#
    )

    static func loadVariables(beside composeFileURL: URL) throws -> [String: String] {
        let envURL = composeFileURL.deletingLastPathComponent().appendingPathComponent(".env")
        guard FileManager.default.fileExists(atPath: envURL.path) else {
            return [:]
        }

        let contents: String
        do {
            contents = try String(contentsOf: envURL, encoding: .utf8)
        } catch {
            throw ComposeError.readFailed(envURL.path, underlying: error)
        }

        return parse(contents)
    }

    package static func parse(_ contents: String) -> [String: String] {
        var variables: [String: String] = [:]

        for line in contents.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            guard let separatorIndex = trimmed.firstIndex(of: "=") else {
                continue
            }

            let key = String(trimmed[..<separatorIndex]).trimmingCharacters(in: .whitespaces)
            guard key.range(of: keyPattern, options: .regularExpression) != nil else {
                continue
            }

            let valueStart = trimmed.index(after: separatorIndex)
            let value = String(trimmed[valueStart...])
            variables[key] = value
        }

        return variables
    }

    package static func substitute(
        _ text: String,
        variables: [String: String],
        composePath: String
    ) throws -> String {
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        var output: [String] = []
        output.reserveCapacity(lines.count)

        for line in lines {
            let lineText = String(line)
            let trimmed = lineText.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                output.append(lineText)
            } else {
                output.append(try substituteLine(lineText, variables: variables, composePath: composePath))
            }
        }

        var result = output.joined(separator: "\n")
        if text.hasSuffix("\n"), !result.isEmpty {
            result += "\n"
        }
        return result
    }

    private static func substituteLine(
        _ text: String,
        variables: [String: String],
        composePath: String
    ) throws -> String {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let matches = placeholderRegex.matches(in: text, options: [], range: fullRange)
        var result = ""
        var lastIndex = 0

        for match in matches {
            guard match.numberOfRanges >= 2 else { continue }

            let matchRange = match.range(at: 0)
            let key = nsText.substring(with: match.range(at: 1))

            result += nsText.substring(with: NSRange(location: lastIndex, length: matchRange.location - lastIndex))

            guard let value = variables[key] else {
                throw ComposeError.unresolvedVariable(name: key, composePath: composePath)
            }
            result += value
            lastIndex = matchRange.location + matchRange.length
        }

        result += nsText.substring(from: lastIndex)
        return result
    }
}
