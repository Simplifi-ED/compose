import ArgumentParser
import ComposeCore
import ContainerAPIClient
import ContainerResource
import ContainerizationOCI
import ContainerizationOS
import Foundation

extension TestRunner {
    mutating func runExecTests() {
        runExecResolverTests()
        runExecIOFlagsTests()
        runExecSessionTests()
    }

    private mutating func runExecResolverTests() {
        runExecResolverSuccessTests()
        runExecResolverErrorTests()
    }

    private mutating func runExecResolverSuccessTests() {
        let runningWeb = ProjectContainer(
            name: "demo_web",
            serviceName: "web",
            status: .running,
            publishedPorts: []
        )
        let runningDb = ProjectContainer(
            name: "demo_db",
            serviceName: "db",
            status: .running,
            publishedPorts: []
        )

        do {
            let resolved = try ExecContainerResolver.resolve(
                projectName: "demo",
                serviceName: "web",
                containers: [runningWeb, runningDb]
            )
            expect(resolved.name == "demo_web", "resolver picks running service container")
        } catch {
            fputs("FAIL: resolver should succeed for single running match: \(error)\n", stderr)
            failures += 1
        }
    }

    private mutating func runExecResolverErrorTests() {
        let runningWeb = ProjectContainer(
            name: "demo_web",
            serviceName: "web",
            status: .running,
            publishedPorts: []
        )
        let stoppedWeb = ProjectContainer(
            name: "demo_web_old",
            serviceName: "web",
            status: .stopped,
            publishedPorts: []
        )

        expectComposeError(
            "service not found",
            matching: { if case .serviceNotFound(service: "missing", project: "demo") = $0 { true } else { false } },
            body: {
                _ = try ExecContainerResolver.resolve(
                    projectName: "demo",
                    serviceName: "missing",
                    containers: [runningWeb]
                )
            }
        )

        expectComposeError(
            "service not running",
            matching: { if case .serviceNotRunning(service: "web", state: "stopped") = $0 { true } else { false } },
            body: {
                _ = try ExecContainerResolver.resolve(
                    projectName: "demo",
                    serviceName: "web",
                    containers: [stoppedWeb]
                )
            }
        )

        runExecResolverAmbiguityTests(runningWeb: runningWeb)
    }

    private mutating func runExecResolverAmbiguityTests(runningWeb: ProjectContainer) {
        let duplicateA = ProjectContainer(
            name: "demo_web_a",
            serviceName: "web",
            status: .running,
            publishedPorts: []
        )
        let duplicateB = ProjectContainer(
            name: "demo_web_b",
            serviceName: "web",
            status: .running,
            publishedPorts: []
        )
        expectComposeError(
            "ambiguous service",
            matching: {
                if case .ambiguousService(service: "web", containers: let names) = $0 {
                    return Set(names) == ["demo_web_a", "demo_web_b"]
                }
                return false
            },
            body: {
                _ = try ExecContainerResolver.resolve(
                    projectName: "demo",
                    serviceName: "web",
                    containers: [duplicateA, duplicateB]
                )
            }
        )

        let unlabeled = ProjectContainer(
            name: "legacy",
            serviceName: nil,
            status: .running,
            publishedPorts: []
        )
        expectComposeError(
            "unlabeled service excluded",
            matching: { if case .serviceNotFound = $0 { true } else { false } },
            body: {
                _ = try ExecContainerResolver.resolve(
                    projectName: "demo",
                    serviceName: "web",
                    containers: [unlabeled]
                )
            }
        )
    }

    private mutating func runExecIOFlagsTests() {
        let explicit = InteractiveSession.IOFlags.resolve(
            explicitInteractive: true,
            explicitTTY: false,
            stdinIsTTY: false
        )
        expect(
            explicit.interactive && !explicit.processTerminal && !explicit.useInteractivePTY,
            "explicit -i without -t"
        )

        let auto = InteractiveSession.IOFlags.resolve(
            explicitInteractive: false,
            explicitTTY: false,
            stdinIsTTY: true
        )
        expect(auto.interactive && auto.processTerminal && auto.useInteractivePTY, "auto -it when stdin is a TTY")

        let piped = InteractiveSession.IOFlags.resolve(
            explicitInteractive: false,
            explicitTTY: false,
            stdinIsTTY: false
        )
        expect(
            !piped.interactive && !piped.processTerminal && !piped.useInteractivePTY,
            "piped stdin stays non-interactive"
        )

        let pipedExplicitTTY = InteractiveSession.IOFlags.resolve(
            explicitInteractive: true,
            explicitTTY: true,
            stdinIsTTY: false
        )
        expect(
            pipedExplicitTTY.interactive && pipedExplicitTTY.processTerminal && !pipedExplicitTTY.useInteractivePTY,
            "-t -i on piped stdin avoids host PTY without stdin TTY"
        )

        let ttyOnlyOnPipe = InteractiveSession.IOFlags.resolve(
            explicitInteractive: false,
            explicitTTY: true,
            stdinIsTTY: false
        )
        expect(
            ttyOnlyOnPipe.processTerminal && !ttyOnlyOnPipe.useInteractivePTY,
            "-t without -i on pipe uses non-TTY interrupt path"
        )
    }

    private mutating func runExecSessionTests() {
        runExecSessionVerifyTargetTests()
        runExecSessionRunMockTests()
    }

    private mutating func runExecSessionVerifyTargetTests() {
        expectComposeError(
            "project label mismatch",
            matching: {
                if case .containerProjectMismatch(container: "demo_web", project: "demo") = $0 {
                    true
                } else {
                    false
                }
            },
            body: {
                try ExecSession.verifyExecTarget(
                    snapshot: Self.makeContainerSnapshot(
                        project: "other",
                        service: "web",
                        status: .running,
                        id: "demo_web"
                    ),
                    configuration: Self.sampleExecConfiguration()
                )
            }
        )

        expectComposeError(
            "container not running at exec time",
            matching: { if case .serviceNotRunning(service: "web", state: "stopped") = $0 { true } else { false } },
            body: {
                try ExecSession.verifyExecTarget(
                    snapshot: Self.makeContainerSnapshot(
                        project: "demo",
                        service: "web",
                        status: .stopped,
                        id: "demo_web"
                    ),
                    configuration: Self.sampleExecConfiguration()
                )
            }
        )
    }

    private mutating func runExecSessionRunMockTests() {
        let exitCode = blockingAwait {
            do {
                try await ExecSession.run(
                    configuration: Self.sampleExecConfiguration(),
                    shutdownContext: Self.sampleShutdownContext(),
                    execBody: { _, _, _, _ in 42 }
                )
                return Int32.min
            } catch let exit as ExitCode {
                return exit.rawValue
            } catch {
                return Int32.min
            }
        }
        expect(exitCode == 42, "exec session maps mocked body exit code")

        let mismatch = blockingAwait {
            do {
                try await ExecSession.run(
                    configuration: Self.sampleExecConfiguration(),
                    shutdownContext: Self.sampleShutdownContext(),
                    getContainer: { _ in
                        Self.makeContainerSnapshot(
                            project: "other",
                            service: "web",
                            status: .running,
                            id: "demo_web"
                        )
                    },
                    execBody: ExecSession.runExecBody
                )
                return false
            } catch is ComposeError {
                return true
            } catch {
                return false
            }
        }
        expect(mismatch, "exec session rejects project label mismatch before ProcessIO")

        runExecSessionProcessMockTests()
    }

    private mutating func runExecSessionProcessMockTests() {
        final class ConfigCapture: @unchecked Sendable {
            var configuration: ProcessConfiguration?
        }
        let capture = ConfigCapture()
        let processExit = blockingAwait {
            do {
                try await ExecSession.run(
                    configuration: Self.sampleExecConfiguration(
                        executable: "/bin/sh",
                        arguments: ["-c", "echo hi"],
                        processTerminal: true
                    ),
                    shutdownContext: Self.sampleShutdownContext(),
                    getContainer: { _ in
                        Self.makeContainerSnapshot(
                            project: "demo",
                            service: "web",
                            status: .running,
                            id: "demo_web"
                        )
                    },
                    createProcess: { _, _, config, _ in
                        capture.configuration = config
                        return MockClientProcess(exitCode: 5)
                    },
                    execBody: ExecSession.runExecBody
                )
                return Int32.min
            } catch let exit as ExitCode {
                return exit.rawValue
            } catch {
                return Int32.min
            }
        }
        expect(processExit == 5, "exec session propagates mocked process exit code")
        expect(capture.configuration?.executable == "/bin/sh", "exec session passes executable without shell wrap")
        expect(capture.configuration?.arguments == ["-c", "echo hi"], "exec session passes arguments verbatim")
        expect(capture.configuration?.terminal == true, "exec session sets process terminal flag")
    }
}

private struct MockClientProcess: ClientProcess {
    let id = "mock-process"
    let exitCode: Int32

    func start() async throws {}

    func resize(_ size: Terminal.Size) async throws {}

    func kill(_ signal: Int32) async throws {}

    func wait() async throws -> Int32 {
        exitCode
    }
}

extension TestRunner {
    static func sampleExecConfiguration(
        executable: String = "/bin/sh",
        arguments: [String] = [],
        processTerminal: Bool = false,
        interactive: Bool = false,
        useInteractivePTY: Bool = false
    ) -> ExecSession.Configuration {
        ExecSession.Configuration(
            containerName: "demo_web",
            projectName: "demo",
            serviceName: "web",
            executable: executable,
            arguments: arguments,
            processTerminal: processTerminal,
            interactive: interactive,
            useInteractivePTY: useInteractivePTY
        )
    }

    static func sampleShutdownContext() -> ProjectShutdownContext {
        ProjectShutdownContext(
            projectName: "demo",
            composeFile: nil,
            fileURLs: nil,
            options: GracefulStopOptions()
        )
    }

}
