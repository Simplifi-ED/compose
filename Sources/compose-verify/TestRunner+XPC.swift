import ComposeCore
import Foundation

extension TestRunner {
    mutating func runXPCTests() {
        runXPCCodecTests()
        runXPCAllowlistTests()
        runXPCPathValidationTests()
        runXPCErrorMappingTests()
    }

    private mutating func runXPCCodecTests() {
        let request = ComposeXPCProjectRequest(
            projectName: "demo",
            files: ["compose.yaml"],
            profiles: ["dev"],
            services: ["web"]
        )
        do {
            let json = try ComposeXPCCodec.encode(request)
            let decoded = try ComposeXPCCodec.decodeRequest(json)
            expect(decoded == request, "XPC request round-trip")
        } catch {
            expect(false, "XPC request round-trip threw: \(error)")
        }

        let status = ComposeXPCStatusResponse(
            exitStatus: 0,
            containers: [
                ComposeXPCContainerRow(name: "demo_web_1", service: "web", state: "running", ports: "")
            ],
            warnings: []
        )
        do {
            let json = try ComposeXPCCodec.encode(status)
            expect(json.contains("\"demo_web_1\""), "XPC status encodes container name")
        } catch {
            expect(false, "XPC status encode threw: \(error)")
        }
    }

    private mutating func runXPCAllowlistTests() {
        let signed = ComposeXPCClientSigningInfo(
            teamID: "TEAM1234",
            bundleID: "com.example.app",
            signatureValid: true
        )
        let allowlist = ComposeXPCAllowlist(teamIDs: ["TEAM1234"], clients: [])
        expect(
            ComposeXPCClientAuth.matchesAllowlist(signed, allowlist: allowlist),
            "team ID allowlist match"
        )
        expect(
            !ComposeXPCClientAuth.matchesAllowlist(
                ComposeXPCClientSigningInfo(teamID: nil, bundleID: nil, signatureValid: false),
                allowlist: allowlist
            ),
            "unsigned client rejected"
        )
        let clientPair = ComposeXPCAllowlist(
            clients: [ComposeXPCAllowlistClient(teamID: "TEAM1234", bundleID: "com.example.app")]
        )
        expect(
            ComposeXPCClientAuth.matchesAllowlist(signed, allowlist: clientPair),
            "team+bundle client allowlist match"
        )
        expect(
            !ComposeXPCClientAuth.matchesAllowlist(
                ComposeXPCClientSigningInfo(teamID: "OTHER", bundleID: "com.example.app", signatureValid: true),
                allowlist: clientPair
            ),
            "bundle ID alone does not match without team ID"
        )
        let emptyClosed = ComposeXPCAllowlist()
        expect(
            !ComposeXPCClientAuth.matchesAllowlist(signed, allowlist: emptyClosed),
            "empty allowlist rejects signed client by default"
        )
        let devAllowlist = ComposeXPCAllowlist(allowAnySigned: true)
        expect(
            ComposeXPCClientAuth.matchesAllowlist(signed, allowlist: devAllowlist),
            "allowAnySigned admits signed client"
        )
    }

    private mutating func runXPCPathValidationTests() {
        do {
            try ComposePathValidation.validateComposeFilePaths(["../escape.yaml"])
            expect(false, "path with .. should throw")
        } catch {
            expect(true, "path with .. rejected")
        }
        do {
            try ComposePathValidation.validateComposeFilePaths(["compose.yaml"])
            expect(true, "valid compose path accepted")
        } catch {
            expect(false, "valid compose path should not throw")
        }
        expectComposeError(
            "padded compose path rejected",
            matching: { if case .invalidComposeFilePath = $0 { true } else { false } },
            body: {
                try ComposePathValidation.validateComposeFilePaths([" compose.yaml "])
            }
        )
    }

    private mutating func runXPCErrorMappingTests() {
        let error = ComposeXPCError.clientNotAllowed("unsigned binary")
        let json = ComposeXPCCodec.errorResponseJSON(from: error)
        expect(json.contains("unsigned binary"), "error JSON includes message")
        expect(json.contains("\"code\":1"), "error JSON includes clientNotAllowed code")
    }

    private mutating func expectThrowsNSError(_ body: () throws -> Void) {
        do {
            try body()
            expect(false, "expected NSError throw")
        } catch {
            let nsError = error as NSError
            expect(nsError.domain == ComposeXPCConstants.errorDomain, "NSError domain is compose XPC")
        }
    }
}
