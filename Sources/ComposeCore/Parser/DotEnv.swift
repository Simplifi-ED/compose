import Foundation

package enum DotEnv {
    private static let keyPattern = #"^[A-Za-z_][A-Za-z0-9_]*$"#

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
}
