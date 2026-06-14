import Foundation

extension HostsFileEditor {
    struct ParsedEntry {
        let address: String
        let hostname: String
        let lineNumber: Int
    }

    static func formattedBlock(
        projectName: String,
        projectID: String,
        hostnames: [String]
    ) -> String {
        let begin = beginMarker(projectName: projectName, projectID: projectID)
        let end = endMarker(projectName: projectName, projectID: projectID)
        let hostLine = "\(loopbackIP) " + hostnames.joined(separator: " ")
        return [begin, hostLine, end].joined(separator: "\n")
    }

    static func parseBeginMarker(_ line: String) -> (projectName: String, projectID: String)? {
        let prefix = "# BEGIN container-compose:"
        guard line.hasPrefix(prefix) else { return nil }
        let remainder = String(line.dropFirst(prefix.count))
        guard let separator = remainder.lastIndex(of: ":") else { return nil }
        let projectName = String(remainder[..<separator])
        let projectID = String(remainder[remainder.index(after: separator)...])
        guard !projectName.isEmpty, !projectID.isEmpty else { return nil }
        return (projectName, projectID)
    }

    static func blockRange(in lines: [String], projectID: String) -> Range<Int>? {
        var index = 0
        while index < lines.count {
            guard let parsed = parseBeginMarker(lines[index]), parsed.projectID == projectID else {
                index += 1
                continue
            }
            let endMarkerLine = endMarker(projectName: parsed.projectName, projectID: parsed.projectID)
            guard let endIndex = lines[index...].firstIndex(of: endMarkerLine) else { return nil }
            return index..<(endIndex + 1)
        }
        return nil
    }

    static func allManagedBlockRanges(in content: String) -> [Range<Int>] {
        let lineList = splitLines(content)
        var ranges: [Range<Int>] = []
        var index = 0
        while index < lineList.count {
            guard let parsed = parseBeginMarker(lineList[index]),
                  let range = blockRange(in: lineList, projectID: parsed.projectID)
            else {
                index += 1
                continue
            }
            ranges.append(range)
            index = range.upperBound
        }
        return ranges
    }

    static func parseEntries(
        in content: String,
        excludingLineRanges: [Range<Int>]
    ) -> [ParsedEntry] {
        let lineList = splitLines(content)
        var entries: [ParsedEntry] = []
        for (offset, line) in lineList.enumerated() {
            if excludingLineRanges.contains(where: { $0.contains(offset) }) { continue }
            let trimmed = line.trimmingCharacters(in: CharacterSet.whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let parts = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard parts.count >= 2 else { continue }
            let address = parts[0]
            for hostname in parts.dropFirst() where !hostname.hasPrefix("#") {
                entries.append(
                    ParsedEntry(
                        address: address,
                        hostname: HostDNSPlanning.normalizedHostname(hostname),
                        lineNumber: offset + 1
                    )
                )
            }
        }
        return entries
    }

    static func hostnamesFromLine(_ line: String) -> [String] {
        let parts = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard parts.count > 1 else { return [] }
        return parts.dropFirst().map { HostDNSPlanning.normalizedHostname($0) }
    }

    static func splitLines(_ content: String) -> [String] {
        content.components(separatedBy: "\n")
    }
}
