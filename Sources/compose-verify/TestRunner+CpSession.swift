import ComposeCore
import Foundation

extension TestRunner {
    mutating func runCpSessionTests() {
        runCpSessionGuardTests()
        runCpSessionCopyTests()
        runCpDryRunTests()
    }

    private mutating func runCpSessionGuardTests() {
        let mismatch = blockingAwait {
            do {
                try await CpSession.run(
                    configuration: Self.sampleCpConfiguration(),
                    copyIn: { _, _, _, _, _ in },
                    copyOut: { _, _, _, _ in },
                    getContainer: { _ in
                        Self.makeContainerSnapshot(
                            project: "other",
                            service: "web",
                            status: .running,
                            id: "demo_web_1"
                        )
                    }
                )
                return false
            } catch let error as ComposeError {
                if case .containerProjectMismatch(container: "demo_web_1", project: "demo") = error {
                    return true
                }
                return false
            } catch {
                return false
            }
        }
        expect(mismatch, "cp session rejects project mismatch before copy")
    }

    private mutating func runCpSessionCopyTests() {
        let snapshot = Self.runCpAllCopyInSession()
        expect(snapshot?.copyInCount == 2, "cp session --all invokes copyIn per replica")
        expect(
            snapshot?.containers == ["demo_web_1", "demo_web_2"],
            "cp session targets each replica container"
        )
    }

    private mutating func runCpDryRunTests() {
        let manifest = DryRunManifest()
        blockingAwait {
            await manifest.recordCp(
                container: "demo_web_1",
                direction: .copyOut,
                source: "/etc/hostname",
                destination: "./hostname"
            )
        }
        let lines = blockingAwait { await manifest.sortedLines() }
        expect(lines.count == 1, "cp dry-run records one line")
        expect(
            lines[0] == """
            [DRY-RUN] cp container "demo_web_1" direction=out source="/etc/hostname" destination="./hostname"
            """,
            "cp dry-run line format"
        )
    }

    static func runCpAllCopyInSession() -> (copyInCount: Int, containers: Set<String>)? {
        actor CopyRecorder {
            var copyInCount = 0
            var containers: [String] = []

            func recordCopyIn(container: String) {
                copyInCount += 1
                containers.append(container)
            }
        }
        let recorder = CopyRecorder()
        let hostFile = tempCpFile()
        return blockingAwait {
            do {
                try await CpSession.run(
                    configuration: CpSession.Configuration(
                        direction: .copyIn,
                        targets: [Self.cpRunningWebOne, Self.cpRunningWebTwo],
                        projectName: "demo",
                        serviceName: "web",
                        containerPath: "/app/file.txt",
                        hostPath: hostFile.path,
                        rawHostPath: hostFile.path
                    ),
                    copyIn: { container, _, _, _, _ in
                        await recorder.recordCopyIn(container: container)
                    },
                    copyOut: { _, _, _, _ in },
                    getContainer: { id in
                        makeContainerSnapshot(
                            project: "demo",
                            service: "web",
                            status: .running,
                            id: id
                        )
                    }
                )
                let copyInCount = await recorder.copyInCount
                let containers = await recorder.containers
                return (copyInCount, Set(containers))
            } catch {
                fputs("FAIL: cp session copy-in should succeed: \(error)\n", stderr)
                return nil
            }
        }
    }

    static func sampleCpConfiguration() -> CpSession.Configuration {
        CpSession.Configuration(
            direction: .copyOut,
            targets: [Self.cpRunningWebOne],
            projectName: "demo",
            serviceName: "web",
            containerPath: "/etc/hostname",
            hostPath: "/tmp/hostname",
            rawHostPath: "./hostname"
        )
    }

    static func tempCpFile() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("compose-cp-\(UUID().uuidString).txt")
        FileManager.default.createFile(atPath: url.path, contents: Data("cp".utf8))
        return url
    }
}
