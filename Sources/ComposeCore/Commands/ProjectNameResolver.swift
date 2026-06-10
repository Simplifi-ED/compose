import Foundation

package enum ProjectNameResolver {
    package static func resolve(
        cliProjectName: String?,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        composeName: String?,
        firstFileURL: URL?
    ) throws -> String {
        if let cliProjectName, !cliProjectName.isEmpty {
            return try normalize(cliProjectName)
        }
        if let envName = environment["COMPOSE_PROJECT_NAME"], !envName.isEmpty {
            return try normalize(envName)
        }
        if let composeName, !composeName.isEmpty {
            return try normalize(composeName)
        }
        if let firstFileURL {
            let directoryName = firstFileURL.deletingLastPathComponent().lastPathComponent
            if !directoryName.isEmpty, directoryName != "/" {
                return try normalize(directoryName)
            }
        }
        return try normalize("default")
    }

    package static func normalize(_ name: String) throws -> String {
        let lowered = name.lowercased()
        var normalized = ""
        normalized.reserveCapacity(lowered.count)

        for character in lowered {
            if character.isLetter || character.isNumber || character == "-" || character == "_" {
                normalized.append(character)
            } else {
                normalized.append("-")
            }
        }

        while normalized.contains("--") {
            normalized = normalized.replacingOccurrences(of: "--", with: "-")
        }

        normalized = normalized.trimmingCharacters(in: CharacterSet(charactersIn: "-_"))

        guard let first = normalized.first, first.isLetter || first.isNumber else {
            throw ComposeError.invalidProjectName(name)
        }

        guard !normalized.isEmpty else {
            throw ComposeError.invalidProjectName(name)
        }

        return normalized
    }
}
