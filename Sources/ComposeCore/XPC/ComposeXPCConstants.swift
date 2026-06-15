import Foundation

package enum ComposeXPCConstants {
    package static let machServiceName = "com.simplifi-ed.container-compose.xpc"
    package static let errorDomain = "com.simplifi-ed.container-compose.xpc"

    package static let clientsConfigRelativePath = "container-compose/xpc-clients.json"

    package static func configDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
    }

    package static func clientsConfigURL() -> URL {
        configDirectory().appendingPathComponent(clientsConfigRelativePath)
    }

    package static let launchAgentLabel = machServiceName
    package static let launchAgentPlistName = "\(machServiceName).plist"
}
