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
