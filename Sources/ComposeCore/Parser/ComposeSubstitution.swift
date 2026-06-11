import Foundation

package enum ComposeSubstitution {
    private static let nameFirstCharacter = CharacterSet.letters.union(CharacterSet(charactersIn: "_"))
    private static let nameBodyCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))

    package static func resolveVariables(
        beside composeFileURL: URL,
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> [String: String] {
        let envURL = composeFileURL.deletingLastPathComponent().appendingPathComponent(".env")
        let envFiles = FileManager.default.fileExists(atPath: envURL.path) ? [envURL] : []
        return try resolveVariables(envFiles: envFiles, processEnvironment: processEnvironment)
    }

    package static func resolveVariables(
        envFiles: [URL],
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> [String: String] {
        var variables: [String: String] = [:]
        if !envFiles.isEmpty {
            variables = try DotEnv.loadVariables(from: envFiles)
        }
        for (key, value) in processEnvironment {
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
        var result = ""
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            guard character == "$" else {
                result.append(character)
                index = text.index(after: index)
                continue
            }

            let afterDollar = text.index(after: index)
            guard afterDollar < text.endIndex else {
                result.append("$")
                break
            }

            if text[afterDollar] == "$" {
                result.append("$")
                index = text.index(after: afterDollar)
                continue
            }

            guard text[afterDollar] == "{" else {
                result.append("$")
                index = afterDollar
                continue
            }

            if let expansion = try parseBracedExpansion(
                text,
                startingAt: afterDollar,
                variables: variables,
                composePath: composePath
            ) {
                result += expansion.value
                index = expansion.endIndex
            } else {
                result.append("$")
                index = afterDollar
            }
        }

        return result
    }

    private struct ExpansionResult {
        let value: String
        let endIndex: String.Index
    }

    private static func parseBracedExpansion(
        _ text: String,
        startingAt openBrace: String.Index,
        variables: [String: String],
        composePath: String
    ) throws -> ExpansionResult? {
        guard text[openBrace] == "{" else {
            return nil
        }

        var index = text.index(after: openBrace)
        guard let nameEnd = parseNameEnd(in: text, startingAt: index) else {
            return nil
        }
        let name = String(text[index..<nameEnd])
        index = nameEnd

        let modifier: Modifier
        if index < text.endIndex, text[index] == ":" {
            let next = text.index(after: index)
            guard next < text.endIndex, text[next] == "-" else {
                return nil
            }
            modifier = .defaultIfUnsetOrEmpty
            index = text.index(after: next)
        } else if index < text.endIndex, text[index] == "-" {
            modifier = .defaultIfUnset
            index = text.index(after: index)
        } else {
            modifier = .required
        }

        guard let closeBrace = text[index...].firstIndex(of: "}"), closeBrace < text.endIndex else {
            return nil
        }

        let defaultValue = String(text[index..<closeBrace])
        let resolved = try resolve(
            name: name,
            modifier: modifier,
            defaultValue: defaultValue,
            variables: variables,
            composePath: composePath
        )
        return ExpansionResult(value: resolved, endIndex: text.index(after: closeBrace))
    }

    private enum Modifier {
        case required
        case defaultIfUnset
        case defaultIfUnsetOrEmpty
    }

    private static func parseNameEnd(in text: String, startingAt index: String.Index) -> String.Index? {
        guard index < text.endIndex else {
            return nil
        }

        let first = text[index]
        guard let scalar = first.unicodeScalars.first, nameFirstCharacter.contains(scalar) else {
            return nil
        }

        var current = text.index(after: index)
        while current < text.endIndex {
            guard let scalar = text[current].unicodeScalars.first,
                  nameBodyCharacters.contains(scalar) else {
                break
            }
            current = text.index(after: current)
        }

        guard current > index else {
            return nil
        }
        return current
    }

    private static func resolve(
        name: String,
        modifier: Modifier,
        defaultValue: String,
        variables: [String: String],
        composePath: String
    ) throws -> String {
        switch modifier {
        case .required:
            guard let value = variables[name] else {
                throw ComposeError.unresolvedVariable(name: name, composePath: composePath)
            }
            return value
        case .defaultIfUnset:
            if let value = variables[name] {
                return value
            }
            return defaultValue
        case .defaultIfUnsetOrEmpty:
            guard let value = variables[name], !value.isEmpty else {
                return defaultValue
            }
            return value
        }
    }

}
