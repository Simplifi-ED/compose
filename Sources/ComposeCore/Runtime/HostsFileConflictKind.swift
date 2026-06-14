import Foundation

package enum HostsFileConflictKind: Sendable, Equatable {
    case foreignIP(address: String, line: Int)
    case duplicateLoopback(line: Int)
    case managedByOtherProject(projectName: String, line: Int)
}
