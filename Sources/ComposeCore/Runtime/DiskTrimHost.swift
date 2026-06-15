import Darwin
import Foundation

/// Host filesystem checks for APFS sparse trim (macOS only).
package enum DiskTrimHost {
    /// Pinned helper image for privileged guest `fstrim` (not `:latest`).
    package static let trimHelperImage = "docker.io/library/busybox:1.36.1"

    package static func isAPFS(path: String) -> Bool {
        let standardized = (path as NSString).standardizingPath
        var pathToCheck = standardized
        var isDirectory: ObjCBool = false
        if !FileManager.default.fileExists(atPath: standardized, isDirectory: &isDirectory),
           isDirectory.boolValue == false {
            pathToCheck = (standardized as NSString).deletingLastPathComponent
        }
        guard !pathToCheck.isEmpty else { return false }
        var stat = statfs()
        guard pathToCheck.withCString({ statfs($0, &stat) }) == 0 else { return false }
        return withUnsafePointer(to: &stat.f_fstypename) { pointer in
            String(cString: UnsafeRawPointer(pointer).assumingMemoryBound(to: CChar.self)) == "apfs"
        }
    }

    package static func containerRootfsPath(containerID: String, appRoot: String) -> String {
        (appRoot as NSString)
            .appendingPathComponent("containers")
            .appending("/\(containerID)/rootfs.ext4")
    }

    /// Default macOS container app root when `container system status` is unavailable.
    package static func defaultAppRoot() -> String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.container", isDirectory: true)
            .path
    }
}
