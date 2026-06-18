import ComposeCore
import ContainerResource
import ContainerizationExtras
import Foundation

extension TestRunner {
    mutating func runPsTests() {
        runPsRowBuildTests()
        runPsFilterTests()
        runPsStateFormatTests()
        runPsPortFormatTests()
        runPsIPFormatTests()
        runPsTableOutputTests()
        runPsEmptyProjectTests()
    }

    private mutating func runPsRowBuildTests() {
        let web = ProjectContainer(
            name: "demo_web",
            serviceName: "web",
            status: .running,
            publishedPorts: [],
            networkAttachments: []
        )
        let legacy = ProjectContainer(
            name: "legacy",
            serviceName: nil,
            status: .stopped,
            publishedPorts: [],
            networkAttachments: []
        )
        let rows = ProjectStatus.rows(from: [web, legacy], filter: nil)
        expect(rows.count == 2, "row build includes all project containers")
        expect(rows[0].name == "demo_web", "first row name from container id")
        expect(rows[0].service == "web", "service from compose label")
        expect(rows[0].state == "running", "state from runtime status")
        expect(rows[1].service == "", "missing service label yields empty cell")
        expect(rows[1].state == "stopped", "stopped containers included")
    }

    private mutating func runPsFilterTests() {
        let containers = [
            ProjectContainer(name: "demo_web", serviceName: "web", status: .running, publishedPorts: []),
            ProjectContainer(name: "demo_db", serviceName: "db", status: .running, publishedPorts: [])
        ]
        let allRows = ProjectStatus.rows(from: containers, filter: nil)
        expect(allRows.count == 2, "nil filter lists all services")

        let webOnly = ProjectStatus.rows(from: containers, filter: ["web"])
        expect(webOnly.count == 1, "service filter limits rows")
        expect(webOnly[0].service == "web", "filtered row matches requested service")

        let unlabeled = ProjectContainer(
            name: "legacy",
            serviceName: nil,
            status: .stopped,
            publishedPorts: []
        )
        let filteredUnlabeled = ProjectStatus.rows(from: [unlabeled], filter: ["web"])
        expect(filteredUnlabeled.isEmpty, "containers without service label excluded by filter")
    }

    private mutating func runPsStateFormatTests() {
        expect(ProjectStatus.formatState(.running) == "running", "running state raw value")
        expect(ProjectStatus.formatState(.stopped) == "stopped", "stopped state raw value")
        expect(ProjectStatus.formatState(.stopping) == "stopping", "stopping state raw value")
        expect(ProjectStatus.formatState(.unknown) == "unknown", "unknown state raw value")
    }

    private mutating func runPsPortFormatTests() {
        do {
            let tcp = try PublishPort(
                hostAddress: try IPAddress("127.0.0.1"),
                hostPort: 18080,
                containerPort: 80,
                proto: .tcp,
                count: 1
            )
            expect(
                ProjectStatus.formatPorts([tcp]) == "127.0.0.1:18080->80/tcp",
                "single TCP port formats docker-style"
            )

            let udp = try PublishPort(
                hostAddress: try IPAddress("127.0.0.1"),
                hostPort: 5353,
                containerPort: 53,
                proto: .udp,
                count: 1
            )
            expect(
                ProjectStatus.formatPorts([tcp, udp]) == "127.0.0.1:18080->80/tcp, 127.0.0.1:5353->53/udp",
                "multiple ports join with comma space"
            )

            let range = try PublishPort(
                hostAddress: try IPAddress("127.0.0.1"),
                hostPort: 9000,
                containerPort: 8000,
                proto: .tcp,
                count: 2
            )
            expect(
                ProjectStatus.formatPorts([range]) == "127.0.0.1:9000->8000/tcp, 127.0.0.1:9001->8001/tcp",
                "count greater than one expands port range"
            )
        } catch {
            fputs("FAIL: unexpected port fixture error: \(error)\n", stderr)
            failures += 1
        }
    }

    private mutating func runPsIPFormatTests() {
        do {
            let cidr = try CIDRv4("192.168.64.32/24")
            let attachment = Attachment(
                network: "demo_backend",
                hostname: "demo_web_1",
                ipv4Address: cidr,
                ipv4Gateway: try IPv4Address("192.168.64.1"),
                ipv6Address: nil,
                macAddress: nil
            )
            let container = ProjectContainer(
                name: "demo_web_1",
                serviceName: "web",
                status: .running,
                publishedPorts: [],
                networkAttachments: [attachment]
            )
            expect(
                ProjectStatus.formatIP(container: container, projectName: nil, composeFile: nil) == "192.168.64.32",
                "running container formats primary IPv4"
            )
            let stopped = ProjectContainer(
                name: "demo_web_1",
                serviceName: "web",
                status: .stopped,
                publishedPorts: [],
                networkAttachments: [attachment]
            )
            expect(
                ProjectStatus.formatIP(container: stopped, projectName: nil, composeFile: nil).isEmpty,
                "stopped container omits IP"
            )
            expect(
                ContainerNetworkDiscovery.ipv4HostAddress(cidr) == "192.168.64.32",
                "container network discovery host address"
            )
        } catch {
            fputs("FAIL: unexpected IP fixture error: \(error)\n", stderr)
            failures += 1
        }
    }

    private mutating func runPsTableOutputTests() {
        let table = ProjectStatus.defaultTable()
        let row = ProjectStatusRow(
            name: "demo_web",
            service: "web",
            state: "running",
            ipAddress: "192.168.64.32",
            ports: "127.0.0.1:18080->80/tcp"
        )
        let plain = table.formatRow(row.cells)
        expect(plain.contains("demo_web"), "table row includes container name")
        expect(plain.contains("running"), "table row includes state")
        expect(!plain.contains("\u{001B}["), "table row has no escape sequences")

        let longPorts = String(repeating: "9", count: 40)
        let truncated = table.formatRow(["demo_web", "web", "running", "", longPorts])
        expect(truncated.hasSuffix("…"), "long ports cell truncates without wrapping")
        expect(!truncated.contains("\n"), "table row is single line")

        let pipeHeader = table.formatHeader(mode: .pipe)
        expect(!pipeHeader.contains("\u{001B}["), "pipe header has no escape sequences")
    }

    private mutating func runPsEmptyProjectTests() {
        let rows = ProjectStatus.rows(from: [], filter: nil)
        expect(rows.isEmpty, "empty project yields no data rows")

        let table = ProjectStatus.defaultTable()
        let header = table.formatHeader(mode: .plain)
        expect(header.contains("NAME"), "empty project still formats header")
        expect(header.contains("PORTS"), "header includes ports column")
    }
}
