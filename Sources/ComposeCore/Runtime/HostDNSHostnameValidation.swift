import Foundation

package enum HostDNSHostnameValidation {
    private static let devSuffixes = [
        ".local",
        ".test",
        ".localhost",
        ".invalid",
        ".example"
    ]

    package static func isDevSuffixHostname(_ hostname: String) -> Bool {
        let lower = hostname.lowercased()
        return devSuffixes.contains { lower.hasSuffix($0) }
    }

    package static func normalizedHostname(_ hostname: String) -> String {
        hostname.lowercased()
    }

    package static func invalidHostnameReason(_ hostname: String) -> String? {
        let trimmed = hostname.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "hostname must not be empty"
        }
        if trimmed.contains(where: \.isWhitespace) {
            return "hostname must not contain whitespace"
        }
        if trimmed.contains("/") || trimmed.contains("\\") {
            return "path characters not allowed"
        }
        if trimmed.contains("..") {
            return "hostname must not contain '..'"
        }
        if trimmed.hasPrefix(".") || trimmed.hasSuffix(".") {
            return "hostname must not start or end with '.'"
        }
        if trimmed.count > 253 {
            return "hostname must not exceed 253 characters"
        }
        let labels = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        for label in labels {
            if label.hasPrefix("-") || label.hasSuffix("-") {
                return "hostname labels must not start or end with '-'"
            }
            if label.count > 63 {
                return "hostname labels must not exceed 63 characters"
            }
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
        if trimmed.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            return "hostname contains invalid characters"
        }
        return nil
    }
}
