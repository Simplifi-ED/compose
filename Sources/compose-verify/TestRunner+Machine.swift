import ArgumentParser
import ComposeCore
import Foundation

extension TestRunner {
    mutating func runMachineTests() {
        runMachineNameValidationTests()
        runMachineBannerTests()
        runMachineLabelTests()
        do {
            try runMachinePlannerTests()
        } catch {
            fputs("FAIL: machine planner tests: \(error)\n", stderr)
            failures += 1
        }
        runMachineUnsupportedCommandTests()
        runMachineDryRunTests()
        runMachineLazyBootTests()
        runMachineStagingRootTests()
    }

    private mutating func runMachineNameValidationTests() {
        expectComposeError(
            "invalid machine name uppercase",
            matching: { if case .invalidMachineName = $0 { true } else { false } },
            body: {
                let options = try MachineOptions.parse(["--machine", "Dev"])
                try options.validateMachineName()
            }
        )

        expectComposeError(
            "invalid machine name special character",
            matching: { if case .invalidMachineName = $0 { true } else { false } },
            body: {
                let options = try MachineOptions.parse(["--machine", "dev!"])
                try options.validateMachineName()
            }
        )

        expectComposeError(
            "whitespace-only machine name",
            matching: { if case .invalidMachineName("") = $0 { true } else { false } },
            body: {
                let options = try MachineOptions.parse(["--machine", "   "])
                try options.validateMachineName()
            }
        )

        do {
            let options = try MachineOptions.parse(["--machine", "dev"])
            try options.validateMachineName()
            expect(true, "valid machine name accepted")
        } catch {
            fputs("FAIL: valid machine name should parse: \(error)\n", stderr)
            failures += 1
        }
    }

    private mutating func runMachineBannerTests() {
        let sandbox = MachineContext.applicationSandbox
        let sandboxCapture = StandardStreamCapture.captureStandardError {
            sandbox.printExecutionBanner()
        }
        expect(
            sandboxCapture.captured.contains("Execution context: application sandbox"),
            "sandbox execution banner"
        )

        let machine = MachineContext(machineName: "dev", snapshot: nil)
        let machineCapture = StandardStreamCapture.captureStandardError {
            machine.printExecutionBanner()
        }
        expect(
            machineCapture.captured.contains("Execution context: container machine 'dev'"),
            "machine execution banner"
        )
    }

    private mutating func runMachineLabelTests() {
        let flags = ComposeLabels.runFlags(
            projectName: "demo",
            serviceName: "web",
            machineName: "dev"
        )
        expect(
            flags.contains("\(ComposeLabels.machine)=dev"),
            "machine label on run flags"
        )
        let sandboxFlags = ComposeLabels.runFlags(projectName: "demo", serviceName: "web")
        expect(
            !sandboxFlags.contains(ComposeLabels.machine),
            "sandbox run flags omit machine label"
        )
    }

    private mutating func runMachinePlannerTests() throws {
        let fixturesDirectory = Self.fixtureURL("minimal-compose.yml").deletingLastPathComponent()
        let composeFile = try ComposeParser.parse(fileURL: Self.fixtureURL("minimal-compose.yml"))
        let layers = try ServicePlanner.startupLayers(
            for: composeFile,
            projectName: "demo",
            composeDirectory: fixturesDirectory,
            machineName: "dev"
        )
        let plan = layers.flatMap { $0 }.first
        expect(plan != nil, "machine planner emits plan")
        if let plan {
            expect(
                plan.runArguments.contains("\(ComposeLabels.machine)=dev"),
                "machine label on startup plan"
            )
        }

        let initCompose = try ComposeParser.parse(fileURL: Self.fixtureURL("init-compose.yml"))
        let initLayers = try ServicePlanner.startupLayers(
            for: initCompose,
            projectName: "demo",
            composeDirectory: fixturesDirectory,
            machineName: "dev"
        )
        let initPlan = initLayers.flatMap { $0 }.first
        expect(initPlan?.runArguments.contains("--init") == true, "machine startup plan passes --init")
        if let initPlan {
            expect(
                initPlan.runArguments.contains("\(ComposeLabels.machine)=dev"),
                "machine init plan keeps machine label"
            )
        }
    }

    private mutating func runMachineUnsupportedCommandTests() {
        expectComposeError(
            "watch rejects --machine",
            matching: {
                if case .machineUnsupportedCommand("watch") = $0 { true } else { false }
            },
            body: {
                let options = try MachineOptions.parse(["--machine", "dev"])
                try options.rejectIfUnsupported(commandName: "watch")
            }
        )
    }

    private mutating func runMachineLazyBootTests() {
        expect(
            !MachineContext.applicationSandbox.isMachineRunning,
            "sandbox is not machine running"
        )
        let stopped = MachineContext(machineName: "dev", snapshot: nil)
        expect(!stopped.isMachineRunning, "machine without snapshot is not running")

        let graceful = try? MachineContext.applyStoppedPolicy(stopped, policy: .gracefulExit)
        let isGracefulStop: Bool = {
            if case .stoppedGracefully = graceful { return true }
            return false
        }()
        expect(isGracefulStop, "graceful policy on stopped machine")

        let notice = StandardStreamCapture.captureStandardError {
            _ = try? MachineContext.applyStoppedPolicy(stopped, policy: .gracefulExit)
        }
        expect(
            notice.captured.contains("Machine 'dev' is stopped. No active containers."),
            "graceful policy prints stopped notice"
        )

        expectComposeError(
            "requireRunning policy on stopped machine",
            matching: {
                if case .machineStopped("dev", .startRequired) = $0 { true } else { false }
            },
            body: {
                _ = try MachineContext.applyStoppedPolicy(stopped, policy: .requireRunning)
            }
        )

        let startMessage = ComposeError.machineStopped("dev", reason: .startRequired).localizedDescription
        expect(
            startMessage.contains("Machine 'dev' is stopped."),
            "startRequired message uses stopped prefix"
        )
        let readMessage = MachineStoppedReason.noActiveContainers.message(machineName: "dev")
        expect(
            readMessage.contains("Machine 'dev' is stopped.") && readMessage.contains("No active containers"),
            "noActiveContainers message aligned"
        )

        let allowed = try? MachineContext.applyStoppedPolicy(stopped, policy: .allowStopped)
        if case .ready(let context) = allowed {
            expect(context.machineName == "dev", "allowStopped returns inspected context")
        } else {
            expect(false, "allowStopped returns inspected context")
        }
    }

    private mutating func runMachineStagingRootTests() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let root = ComposeFileStaging.stagingRoot().path
        expect(
            root.hasPrefix(home),
            "staging root is under home directory"
        )
        expect(
            root.contains("/.config/container-compose"),
            "staging root uses ~/.config/container-compose"
        )
    }

    private mutating func runMachineDryRunTests() {
        let lines: [String] = blockingAwait {
            let manifest = DryRunManifest(machineName: "dev")
            await manifest.recordExec(container: "demo_web_1", command: ["echo", "hi"])
            return await manifest.sortedLines()
        }
        expect(
            lines.contains(where: { $0.contains("machine=dev") }),
            "dry-run lines include machine prefix"
        )
    }
}
