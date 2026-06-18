import ComposeCore
import Foundation

extension TestRunner {
    mutating func runHostDNSTests() throws {
        try runHostDNSParserTests()
        try runHostDNSPlanningTests()
        try runHostDNSBridgePlanningTests()
        try runHostDNSEditorTests()
        runHostDNSMultiLineBlockTests()
        try runHostDNSConfigTests()
        runHostDNSDryRunTests()
        runHostDNSMachineTests()
    }

    private mutating func runHostDNSParserTests() throws {
        let fixture = try ComposeParser.parse(fileURL: Self.fixtureURL("host-dns-compose.yml"))
        expect(fixture.services["web"]?.hostnames == ["web.demo.local", "api.demo.local"], "x-compose.hosts decode")
    }

    private mutating func runHostDNSPlanningTests() throws {
        let fixtureURL = Self.fixtureURL("host-dns-compose.yml")
        let fixture = try ComposeParser.parse(fileURL: fixtureURL)
        let idA = HostDNSPlanning.projectID(firstComposeFileURL: fixtureURL, projectName: "demo")
        let idB = HostDNSPlanning.projectID(
            firstComposeFileURL: Self.fixtureURL("minimal-compose.yml"),
            projectName: "demo"
        )
        expect(
            idA == HostDNSPlanning.projectID(firstComposeFileURL: fixtureURL, projectName: "demo"),
            "projectID stable"
        )
        expect(idA != idB, "projectID differs by compose file path")

        let plans = HostDNSPlanning.plans(
            composeFile: fixture,
            activeServiceNames: ["web"]
        )
        expect(plans.count == 2, "plans for two hostnames")
        expect(plans.first?.hostPort == "8080", "static host port from publish mapping")

        let warnings = HostDNSPlanning.warnings(
            composeFile: fixture,
            activeServiceNames: ["web"]
        )
        expect(warnings.isEmpty, "dev suffix hostnames produce no warnings")

        let publicService = ComposeService(
            image: "nginx:1.27.3",
            command: nil,
            ports: ["8080:80"],
            environment: nil,
            containerName: nil,
            hostnames: ["github.com"]
        )
        let publicWarnings = HostDNSPlanning.warnings(
            composeFile: ComposeFile(name: nil, services: ["web": publicService]),
            activeServiceNames: ["web"]
        )
        expect(publicWarnings.count == 1, "public suffix warning")
        expect(
            HostDNSPlanning.invalidHostnameReason("-bad.local") != nil,
            "reject label starting with hyphen"
        )
        try runHostDNSPlanningStrictTests()
    }

    private mutating func runHostDNSBridgePlanningTests() throws {
        let bridgeNetwork = ComposeNetwork(mode: .bridge)
        let service = ComposeService(
            image: "nginx:1.27.3",
            command: nil,
            ports: [],
            environment: nil,
            containerName: nil,
            networks: ["backend"],
            hostnames: ["api.demo.local"]
        )
        let composeFile = ComposeFile(
            name: nil,
            services: ["api": service],
            networks: ["backend": bridgeNetwork]
        )
        let strictWarnings = HostDNSPlanning.warnings(
            composeFile: composeFile,
            activeServiceNames: ["api"]
        )
        expect(strictWarnings.isEmpty, "bridge host DNS skips published port warning")

        let bridgePlans = HostDNSPlanning.bridgePlans(
            composeFile: composeFile,
            activeServiceNames: ["api"],
            serviceAddresses: ["api": "10.0.0.42"]
        )
        expect(bridgePlans.count == 1, "bridge plan uses service address")
        expect(bridgePlans[0].targetIP == "10.0.0.42", "bridge plan target IP")

        let identity = HostDNSPlanning.blockIdentity(
            projectName: "demo",
            firstComposeFileURL: Self.fixtureURL("host-dns-compose.yml")
        )
        let merged = HostsFileEditor.mergeBlock(
            content: "",
            identity: identity,
            planned: bridgePlans
        )
        expect(merged.contains("10.0.0.42 api.demo.local"), "hosts block uses bridge IP")
    }

    private mutating func runHostDNSPlanningStrictTests() throws {
        expectComposeError(
            "strict missing port",
            matching: { if case .hostDNSNoPublishedPort = $0 { true } else { false } },
            body: {
                let noPort = try ComposeParser.parse(fileURL: Self.fixtureURL("host-dns-no-port-compose.yml"))
                try HostDNSPlanning.validate(
                    composeFile: noPort,
                    activeServiceNames: ["web"],
                    strict: true
                )
            }
        )

        let softWarnings = HostDNSPlanning.warnings(
            composeFile: try ComposeParser.parse(fileURL: Self.fixtureURL("host-dns-no-port-compose.yml")),
            activeServiceNames: ["web"]
        )
        expect(softWarnings.count == 1, "soft warn on missing published port")
    }

    private mutating func runHostDNSEditorTests() throws {
        let identity = HostDNSPlanning.blockIdentity(
            projectName: "demo",
            firstComposeFileURL: Self.fixtureURL("host-dns-compose.yml")
        )
        let base = """
        127.0.0.1 localhost
        203.0.113.1 web.demo.local
        """
        expectComposeError(
            "external conflict strict",
            matching: { if case .hostDNSExternalConflict = $0 { true } else { false } },
            body: {
                _ = try HostDNSPlanning.validateExternalConflicts(
                    plans: HostDNSPlanning.plans(
                        composeFile: try ComposeParser.parse(fileURL: Self.fixtureURL("host-dns-compose.yml")),
                        activeServiceNames: ["web"]
                    ),
                    hostsContent: base,
                    strict: true
                )
            }
        )

        let mergedOnce = HostsFileEditor.mergeBlock(
            content: "127.0.0.1 localhost\n",
            identity: identity,
            hostnames: ["web.demo.local"]
        )
        let mergedTwice = HostsFileEditor.mergeBlock(
            content: mergedOnce,
            identity: identity,
            hostnames: ["web.demo.local", "api.demo.local"]
        )
        expect(
            mergedTwice.components(separatedBy: identity.beginMarker).count - 1 == 1,
            "replace block instead of double insert"
        )

        let removed = HostsFileEditor.removeBlock(content: mergedTwice, projectID: identity.projectID)
        expect(!removed.contains(identity.beginMarker), "remove block by projectID")
        expect(!removed.contains("# BEGIN container-compose:"), "remove leaves no managed block")
        expect(!removed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "remove keeps non-compose entries")
    }

    private mutating func runHostDNSMultiLineBlockTests() {
        let mixedContent = """
        127.0.0.1 localhost
        # BEGIN container-compose:demo:abc123
        127.0.0.1 web.demo.local
        192.168.64.5 api.demo.local
        # END container-compose:demo:abc123
        """
        let stale = HostsFileEditor.findStaleBlock(content: mixedContent, projectID: "abc123")
        expect(
            stale?.hostnames.sorted() == ["api.demo.local", "web.demo.local"],
            "multi-line block hostnames"
        )
    }

    private mutating func runHostDNSConfigTests() throws {
        let yaml = try ComposeConfigResolver.resolveOutput(
            fileURLs: [Self.fixtureURL("host-dns-compose.yml")],
            activeProfiles: [],
            scaleOverrides: [:]
        )
        expect(yaml?.contains("x-compose:") == true, "config exports x-compose")
        expect(yaml?.contains("web.demo.local") == true, "config exports hostnames")
    }

    private mutating func runHostDNSDryRunTests() {
        let line = DryRunManifestFormatting.formatHostDNSInstall(
            projectName: "demo",
            projectID: "abc123",
            hostnames: ["web.demo.local"]
        )
        expect(line.contains("id=\"abc123\""), "dry-run install includes projectID")
        let removeLine = DryRunManifestFormatting.formatHostDNSRemove(
            projectName: "demo",
            projectID: "abc123"
        )
        expect(removeLine.contains("remove host DNS"), "dry-run remove line")
    }

    private mutating func runHostDNSMachineTests() {
        var disabled = HostDNSOptions()
        disabled.hostDNS = false
        do {
            try disabled.validateMachineCompatibility(machineName: "dev")
        } catch {
            expect(false, "host dns without flag allows machine name")
        }

        expectComposeError(
            "host dns rejects machine",
            matching: { if case .hostDNSUnsupportedWithMachine = $0 { true } else { false } },
            body: {
                var options = HostDNSOptions()
                options.hostDNS = true
                try options.validateMachineCompatibility(machineName: "dev")
            }
        )
    }
}
