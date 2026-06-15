import Foundation

package enum ComposePathValidation {
    package static func validateComposeFilePaths(_ paths: [String]) throws {
        for path in paths {
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw ComposeError.invalidComposeFilePath("Compose file path cannot be empty.")
            }
            if trimmed.contains("..") {
                throw ComposeError.invalidComposeFilePath(
                    "Compose file path cannot contain '..': \(trimmed)"
                )
            }
        }
    }
}
