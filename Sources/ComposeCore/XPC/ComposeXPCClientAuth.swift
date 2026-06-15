import Foundation
import Security

package struct ComposeXPCClientSigningInfo: Sendable, Equatable {
    package let teamID: String?
    package let bundleID: String?
    package let signatureValid: Bool

    package init(teamID: String?, bundleID: String?, signatureValid: Bool) {
        self.teamID = teamID
        self.bundleID = bundleID
        self.signatureValid = signatureValid
    }
}

package enum ComposeXPCClientAuth {
    package static func loadAllowlist() -> ComposeXPCAllowlist {
        let url = ComposeXPCConstants.clientsConfigURL()
        guard let data = try? Data(contentsOf: url) else {
            return ComposeXPCAllowlist()
        }
        return (try? JSONDecoder().decode(ComposeXPCAllowlist.self, from: data)) ?? ComposeXPCAllowlist()
    }

    package static func saveAllowlist(_ allowlist: ComposeXPCAllowlist) throws {
        let directory = ComposeXPCConstants.configDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = ComposeXPCConstants.clientsConfigURL()
        let data = try JSONEncoder().encode(allowlist)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: url.path
        )
    }

    package static func matchesAllowlist(
        _ info: ComposeXPCClientSigningInfo,
        allowlist: ComposeXPCAllowlist
    ) -> Bool {
        guard info.signatureValid else { return false }
        if allowlist.teamIDs.isEmpty, allowlist.bundleIDs.isEmpty {
            return allowlist.allowAnySigned
        }
        if let teamID = info.teamID, allowlist.teamIDs.contains(teamID) {
            return true
        }
        if let bundleID = info.bundleID, allowlist.bundleIDs.contains(bundleID) {
            return true
        }
        return false
    }

    package static func rejectionDetail(for info: ComposeXPCClientSigningInfo) -> String {
        if !info.signatureValid {
            return "unsigned binary (valid code signature required)"
        }
        return "team ID or bundle ID not on the allowlist"
    }

    // ponytail: NSXPCConnection has no public auditToken in container 1.0 SDK; PID guest lookup at accept time.
    package static func signingInfo(from connection: NSXPCConnection) -> ComposeXPCClientSigningInfo {
        signingInfo(fromPID: connection.processIdentifier)
    }

    package static func signingInfo(from auditToken: Data) -> ComposeXPCClientSigningInfo {
        var guest: SecCode?
        let attributes = [kSecGuestAttributeAudit: auditToken] as CFDictionary
        let copyStatus = SecCodeCopyGuestWithAttributes(nil, attributes, [], &guest)
        guard copyStatus == errSecSuccess, let guest else {
            return ComposeXPCClientSigningInfo(teamID: nil, bundleID: nil, signatureValid: false)
        }
        return signingInfo(fromGuest: guest)
    }

    package static func signingInfo(fromPID pid: pid_t) -> ComposeXPCClientSigningInfo {
        var guest: SecCode?
        let attributes = [kSecGuestAttributePid: pid] as CFDictionary
        let copyStatus = SecCodeCopyGuestWithAttributes(nil, attributes, [], &guest)
        guard copyStatus == errSecSuccess, let guest else {
            return ComposeXPCClientSigningInfo(teamID: nil, bundleID: nil, signatureValid: false)
        }
        return signingInfo(fromGuest: guest)
    }

    private static func signingInfo(fromGuest guest: SecCode) -> ComposeXPCClientSigningInfo {
        let validity = SecCodeCheckValidity(guest, [], nil)
        let signatureValid = validity == errSecSuccess

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(guest, [], &staticCode) == errSecSuccess, let staticCode else {
            return ComposeXPCClientSigningInfo(teamID: nil, bundleID: nil, signatureValid: signatureValid)
        }

        var information: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information
        ) == errSecSuccess,
            let dictionary = information as? [String: Any]
        else {
            return ComposeXPCClientSigningInfo(teamID: nil, bundleID: nil, signatureValid: signatureValid)
        }

        let teamID = dictionary[kSecCodeInfoTeamIdentifier as String] as? String
        let bundleID = dictionary[kSecCodeInfoIdentifier as String] as? String
        return ComposeXPCClientSigningInfo(
            teamID: teamID,
            bundleID: bundleID,
            signatureValid: signatureValid
        )
    }

    package static func validate(connection: NSXPCConnection) throws {
        let info = signingInfo(from: connection)
        let allowlist = loadAllowlist()
        guard matchesAllowlist(info, allowlist: allowlist) else {
            throw ComposeXPCError.clientNotAllowed(rejectionDetail(for: info))
        }
    }
}
