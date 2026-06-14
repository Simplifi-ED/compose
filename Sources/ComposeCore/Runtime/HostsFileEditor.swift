import Foundation

/// Reads, merges, and atomically replaces `/etc/hosts` blocks for container-compose host DNS.
package enum HostsFileEditor {
    package static let defaultHostsPath = "/etc/hosts"
    package static let loopbackIP = HostDNSPlanning.targetIP

    package struct ExternalConflict: Sendable, Equatable {
        package let hostname: String
        package let kind: HostsFileConflictKind
    }

    package struct ManagedBlock: Sendable, Equatable {
        package let projectName: String
        package let projectID: String
        package let hostnames: [String]
        package let beginLine: String
        package let endLine: String
    }

    package static func beginMarker(projectName: String, projectID: String) -> String {
        "# BEGIN container-compose:\(projectName):\(projectID)"
    }

    package static func endMarker(projectName: String, projectID: String) -> String {
        "# END container-compose:\(projectName):\(projectID)"
    }

    package static func mergeBlock(
        content: String,
        identity: HostDNSPlanning.BlockIdentity,
        hostnames: [String]
    ) -> String {
        let normalized = hostnames.map { HostDNSPlanning.normalizedHostname($0) }
        let block = formattedBlock(
            projectName: identity.projectName,
            projectID: identity.projectID,
            hostnames: normalized
        )
        let lineList = splitLines(content)
        if let range = blockRange(in: lineList, projectID: identity.projectID) {
            var updated = lineList
            let blockLines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            updated.replaceSubrange(range, with: blockLines)
            return updated.joined(separator: "\n").trimmingCharacters(in: CharacterSet.newlines) + "\n"
        }
        let trimmed = content.trimmingCharacters(in: CharacterSet.newlines)
        if trimmed.isEmpty {
            return block + "\n"
        }
        return trimmed + "\n\n" + block + "\n"
    }

    package static func removeBlock(content: String, projectID: String) -> String {
        let lineList = splitLines(content)
        guard let range = blockRange(in: lineList, projectID: projectID) else {
            return content
        }
        var updated = lineList
        updated.removeSubrange(range)
        while updated.last?.trimmingCharacters(in: CharacterSet.whitespaces).isEmpty == true {
            updated.removeLast()
        }
        guard !updated.isEmpty else { return "" }
        return updated.joined(separator: "\n") + "\n"
    }

    package static func findStaleBlock(content: String, projectID: String) -> ManagedBlock? {
        let lineList = splitLines(content)
        guard let range = blockRange(in: lineList, projectID: projectID),
              let parsed = parseBeginMarker(lineList[range.lowerBound])
        else { return nil }
        let hostLine = lineList[safe: range.lowerBound + 1] ?? ""
        return ManagedBlock(
            projectName: parsed.projectName,
            projectID: parsed.projectID,
            hostnames: hostnamesFromLine(hostLine),
            beginLine: lineList[range.lowerBound],
            endLine: lineList[range.upperBound - 1]
        )
    }

    package static func blocksWithSameProjectName(
        content: String,
        projectName: String,
        excludingProjectID: String
    ) -> [ManagedBlock] {
        let lineList = splitLines(content)
        var blocks: [ManagedBlock] = []
        var index = 0
        while index < lineList.count {
            guard let parsed = parseBeginMarker(lineList[index]),
                  parsed.projectName == projectName,
                  parsed.projectID != excludingProjectID,
                  let range = blockRange(in: lineList, projectID: parsed.projectID)
            else {
                index += 1
                continue
            }
            let hostLine = lineList[safe: range.lowerBound + 1] ?? ""
            blocks.append(
                ManagedBlock(
                    projectName: parsed.projectName,
                    projectID: parsed.projectID,
                    hostnames: hostnamesFromLine(hostLine),
                    beginLine: lineList[range.lowerBound],
                    endLine: lineList[range.upperBound - 1]
                )
            )
            index = range.upperBound
        }
        return blocks
    }

    package static func findConflicts(
        in content: String,
        hostnames: [String],
        excludingProjectID: String? = nil
    ) -> [ExternalConflict] {
        let managedRanges = allManagedBlockRanges(in: content)
        let entries = parseEntries(in: content, excludingLineRanges: managedRanges)
        let wanted = Set(hostnames.map { HostDNSPlanning.normalizedHostname($0) })
        var conflicts: [ExternalConflict] = []
        for entry in entries where wanted.contains(entry.hostname) {
            if entry.address == loopbackIP {
                conflicts.append(
                    ExternalConflict(
                        hostname: entry.hostname,
                        kind: .duplicateLoopback(line: entry.lineNumber)
                    )
                )
            } else {
                conflicts.append(
                    ExternalConflict(
                        hostname: entry.hostname,
                        kind: .foreignIP(address: entry.address, line: entry.lineNumber)
                    )
                )
            }
        }
        if let excludingProjectID {
            conflicts.append(contentsOf: managedBlockConflicts(
                in: content,
                hostnames: wanted,
                excludingProjectID: excludingProjectID
            ))
        }
        return conflicts
    }

    private static func managedBlockConflicts(
        in content: String,
        hostnames: Set<String>,
        excludingProjectID: String
    ) -> [ExternalConflict] {
        let lineList = splitLines(content)
        var conflicts: [ExternalConflict] = []
        var index = 0
        while index < lineList.count {
            guard let parsed = parseBeginMarker(lineList[index]),
                  parsed.projectID != excludingProjectID,
                  let range = blockRange(in: lineList, projectID: parsed.projectID)
            else {
                index += 1
                continue
            }
            let hostLine = lineList[safe: range.lowerBound + 1] ?? ""
            let otherHostnames = Set(hostnamesFromLine(hostLine))
            for hostname in hostnames where otherHostnames.contains(hostname) {
                conflicts.append(
                    ExternalConflict(
                        hostname: hostname,
                        kind: .managedByOtherProject(
                            projectName: parsed.projectName,
                            line: range.lowerBound + 2
                        )
                    )
                )
            }
            index = range.upperBound
        }
        return conflicts
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
