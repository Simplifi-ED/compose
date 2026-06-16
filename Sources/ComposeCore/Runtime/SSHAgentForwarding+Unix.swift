import Darwin
import Foundation

enum SSHUnixSocket {
    static func copyAddressPath(_ path: String, into addr: inout sockaddr_un) {
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        path.withCString { cString in
            withUnsafeMutablePointer(to: &addr.sun_path) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { dest in
                    strncpy(dest, cString, capacity - 1)
                    dest[capacity - 1] = 0
                }
            }
        }
    }

    static func addressLength(path: String) -> socklen_t {
        let offset = MemoryLayout.offset(of: \sockaddr_un.sun_path)!
        return socklen_t(offset + path.utf8.count + 1)
    }

    static func prepareAddress(path: String) -> sockaddr_un {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        copyAddressPath(path, into: &addr)
        let length = addressLength(path: path)
        addr.sun_len = UInt8(truncatingIfNeeded: length)
        return addr
    }

    static func canConnect(at path: String) -> Bool {
        let clientFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard clientFD >= 0 else { return false }
        defer { close(clientFD) }

        var addr = prepareAddress(path: path)
        let length = addressLength(path: path)
        let result = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                connect(clientFD, sockaddrPointer, length)
            }
        }
        return result == 0
    }
}
