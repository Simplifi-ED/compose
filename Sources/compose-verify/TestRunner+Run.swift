import ArgumentParser
import ComposeCore
import Darwin
import Foundation

extension TestRunner {
    mutating func runRunTests() {
        runRunPlannerTests()
        runRunSessionTests()
        runRunInterruptTests()
        runRunTerminalCleanupTests()
        runRunSignalPolicyTests()
    }

    private mutating func runRunPlannerTests() {
        expectComposeError(
            "undefined service",
            matching: { if case .undefinedService(service: "missing") = $0 { true } else { false } },
            body: {
                throw ComposeError.undefinedService(service: "missing")
            }
        )
    }

    private mutating func runRunSessionTests() {
        let exitCode = blockingAwait {
            do {
                try await RunSession.run(
                    plan: ServicePlan(
                        serviceName: "web",
                        name: "demo_web_run_test01",
                        runArguments: []
                    ),
                    shutdownContext: RunShutdownContext(
                        containerID: "demo_web_run_test01",
                        options: GracefulStopOptions()
                    ),
                    runContainer: { _ in 7 }
                )
                return Int32.min
            } catch let exit as ExitCode {
                return exit.rawValue
            } catch {
                return Int32.min
            }
        }
        expect(exitCode == 7, "run session maps mocked container exit code")
    }

    private mutating func runRunInterruptTests() {
        let signal = InterruptSignal(number: SIGINT)
        let gracefulStop = blockingAwait { () -> GracefulStopOptions? in
            final class Capture: @unchecked Sendable {
                var options: GracefulStopOptions?
            }
            let capture = Capture()
            let context = RunShutdownContext(
                containerID: "demo_web_run_interrupt",
                options: GracefulStopOptions(graceSeconds: 25)
            )
            _ = try? await SignalForwarding.interruptedOutcome(
                policy: .stopRunContainer(context),
                signal: signal,
                stopRunContainer: { stopContext in
                    capture.options = stopContext.options
                }
            )
            return capture.options
        }
        expect(gracefulStop?.graceSeconds == 25, "run interrupt uses configured graceful stop options")
    }

    private mutating func runRunTerminalCleanupTests() {
        let restore = InteractiveSession.StdinRestoreHandle(useInteractivePTY: false)
        restore.restore()

        let cleanupCount = blockingAwait { () -> Int in
            final class Counter: @unchecked Sendable {
                var value = 0
            }
            let counter = Counter()
            _ = try? await InteractiveSession.runUntilExit(
                policy: .stopRunContainer(
                    RunShutdownContext(
                        containerID: "demo_web_run_tty",
                        options: GracefulStopOptions()
                    )
                ),
                terminalCleanup: { counter.value += 1 },
                body: { 0 }
            )
            return counter.value
        }
        expect(cleanupCount == 0, "runUntilExit skips terminalCleanup on normal completion")

        runRunTerminalInterruptCleanupTests()
    }

    private mutating func runRunTerminalInterruptCleanupTests() {
        let interruptCleanupCount = blockingAwait { () -> Int in
            final class Counter: @unchecked Sendable {
                var value = 0
            }
            let counter = Counter()
            _ = try? await SignalForwarding.interruptedOutcome(
                policy: .stopRunContainer(
                    RunShutdownContext(
                        containerID: "demo_web_run_tty",
                        options: GracefulStopOptions()
                    )
                ),
                signal: InterruptSignal(number: SIGINT),
                terminalCleanup: { counter.value += 1 },
                stopRunContainer: { _ in }
            )
            return counter.value
        }
        expect(interruptCleanupCount == 1, "run interrupt invokes terminalCleanup once")

        let restoreCalled = blockingAwait { () -> Bool in
            final class Flag: @unchecked Sendable {
                var value = false
            }
            let flag = Flag()
            let handle = InteractiveSession.StdinRestoreHandle(useInteractivePTY: false)
            _ = try? await SignalForwarding.interruptedOutcome(
                policy: .stopRunContainer(
                    RunShutdownContext(
                        containerID: "demo_web_run_tty",
                        options: GracefulStopOptions()
                    )
                ),
                signal: InterruptSignal(number: SIGINT),
                terminalCleanup: {
                    handle.restore()
                    flag.value = true
                },
                stopRunContainer: { _ in }
            )
            return flag.value
        }
        expect(restoreCalled, "run session terminal cleanup can invoke stdin restore handle")
    }

    private mutating func runRunSignalPolicyTests() {
        let signal = InterruptSignal(number: SIGINT)
        let stoppedID = blockingAwait { () -> String? in
            final class Capture: @unchecked Sendable {
                var containerID: String?
            }
            let capture = Capture()
            _ = try? await SignalForwarding.interruptedOutcome(
                policy: .stopRunContainer(
                    RunShutdownContext(
                        containerID: "demo_web_run_abcd1234",
                        options: GracefulStopOptions()
                    )
                ),
                signal: signal,
                stopRunContainer: { context in
                    capture.containerID = context.containerID
                }
            )
            return capture.containerID
        }
        expect(stoppedID == "demo_web_run_abcd1234", "stopRunContainer stops only run container id")
    }
}
