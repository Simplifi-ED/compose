import Foundation

package enum DoctorVersion {
    package static func parse(_ text: String) -> String? {
        let pattern = #/(?:version|container CLI version)\s+(\d+\.\d+\.\d+)/#
        guard let match = text.firstMatch(of: pattern) else { return nil }
        return String(match.1)
    }

    package static func satisfiesMinimum(_ version: String, minimum: String) -> Bool {
        compare(version, minimum) != .orderedAscending
    }

    package static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = lhs.split(separator: ".").compactMap { Int($0) }
        let right = rhs.split(separator: ".").compactMap { Int($0) }
        let count = max(left.count, right.count)
        for index in 0..<count {
            let leftPart = index < left.count ? left[index] : 0
            let rightPart = index < right.count ? right[index] : 0
            if leftPart < rightPart { return .orderedAscending }
            if leftPart > rightPart { return .orderedDescending }
        }
        return .orderedSame
    }
}
