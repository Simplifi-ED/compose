import ComposeCore
import Foundation
import TerminalProgress

extension TestRunner {
    mutating func runImagePullProgressTests() {
        runImagePullFormatTests()
        runImagePullPlainOutputTests()
        runImagePullSilentOutputTests()
        runImagePullInteractiveOutputTests()
        runImagePullPipeOutputTests()
        runImagePullFailedOutputTests()
        runImagePullTargetDedupTests()
        runImagePullRuntimeProgressInsertionTests()
        runImagePullRuntimeProgressGuardTests()
    }

    private mutating func runImagePullFormatTests() {
        var state = ImagePullState()
        state.apply([
            .setDescription("Fetching image"),
            .setTotalItems(4),
            .addItems(2),
            .setTotalSize(8_192),
            .addSize(4_096)
        ])
        let line = ImagePullFormat.statusLine(
            reference: "nginx:1.27.3",
            state: state,
            mode: .plain,
            width: 12
        )
        expect(line.contains("nginx:1.27.3| Pulling"), "image pull line names reference and action")
        expect(line.contains("layer 2/4"), "image pull line includes layer counts")
        expect(line.contains("/"), "image pull line includes byte progress")

        state.apply([.setDescription("Unpacking image")])
        expect(
            ImagePullFormat.statusLine(reference: "nginx", state: state, mode: .plain).contains("Unpacking"),
            "description updates unpacking phase"
        )

        expect(ImagePullFormat.phase(from: "complete") == .complete, "complete description maps to complete phase")
        expect(ImagePullFormat.phase(from: "done pulling") == .complete, "done description maps to complete phase")
    }

    private mutating func runImagePullPlainOutputTests() {
        let buffer = LineBuffer()
        blockingAwait {
            let progress = ImagePullProgress(display: .plain) { buffer.append($0) }
            await progress.begin(references: ["nginx:1.27.3"])
            await progress.apply([.setTotalItems(2), .addItems(1)], to: "nginx:1.27.3")
            await progress.markComplete(reference: "nginx:1.27.3", succeeded: true)
            await progress.finish()
        }
        expect(buffer.lines.count == 3, "plain image pull writes begin, update, completion")
        expect(buffer.lines.last?.contains("Pull complete") == true, "plain image pull writes completion")
    }

    private mutating func runImagePullSilentOutputTests() {
        let buffer = LineBuffer()
        blockingAwait {
            let progress = ImagePullProgress(display: .silent) { buffer.append($0) }
            await progress.begin(references: ["nginx"])
            await progress.apply([.addItems(1)], to: "nginx")
            await progress.markComplete(reference: "nginx", succeeded: true)
            await progress.finish()
        }
        expect(buffer.lines.isEmpty, "silent image pull writes nothing")
    }

    private mutating func runImagePullInteractiveOutputTests() {
        let buffer = LineBuffer()
        let writeCountAfterFinish = blockingAwait { () -> Int in
            let progress = ImagePullProgress(display: .interactive) { buffer.append($0) }
            await progress.begin(references: ["nginx"])
            await progress.markComplete(reference: "nginx", succeeded: true)
            let count = buffer.lines.count
            await progress.finish()
            try? await Task.sleep(for: .milliseconds(200))
            return count
        }
        let output = buffer.lines.joined()
        expect(output.contains("\r\u{001B}[K"), "interactive image pull uses clear-line redraw")
        expect(stripANSI(output).contains("✔ nginx   | Pull complete"), "interactive image pull completion renders")
        expect(buffer.lines.count >= writeCountAfterFinish, "interactive image pull finishes without clearing output")
    }

    private mutating func runImagePullPipeOutputTests() {
        let buffer = LineBuffer()
        blockingAwait {
            let progress = ImagePullProgress(display: .plain, pipeOutput: true) { buffer.append($0) }
            await progress.begin(references: ["nginx"])
            await progress.apply([.setTotalItems(2), .addItems(1)], to: "nginx")
            await progress.markComplete(reference: "nginx", succeeded: true)
            await progress.markComplete(reference: "nginx", succeeded: true)
        }
        expect(
            buffer.lines == ["nginx   | Pulling (layer 1/2)\n", "nginx   | Pull complete\n"],
            "pipe image pull writes layer update and one completion line"
        )
    }

    private mutating func runImagePullFailedOutputTests() {
        let buffer = LineBuffer()
        blockingAwait {
            let progress = ImagePullProgress(display: .plain) { buffer.append($0) }
            await progress.begin(references: ["nginx"])
            await progress.markComplete(reference: "nginx", succeeded: false)
            await progress.finish()
        }
        expect(buffer.lines.last?.contains("Pull failed") == true, "failed image pull writes failure status")
    }

    private mutating func runImagePullTargetDedupTests() {
        let plans = [
            ServicePlan(
                serviceName: "web",
                name: "demo_web_1",
                image: "nginx",
                runArguments: ["--platform", "linux/amd64", "nginx"]
            ),
            ServicePlan(
                serviceName: "web",
                name: "demo_web_2",
                image: "nginx",
                runArguments: ["--platform", "linux/x86_64", "nginx"]
            ),
            ServicePlan(serviceName: "db", name: "demo_db_1", image: "postgres", runArguments: ["postgres"])
        ]
        let targets = ImagePullRunner.pullTargets(for: plans)
        expect(targets.count == 2, "image pull targets dedupe by image and normalized platform")
        if let firstTarget = targets.first {
            expect(firstTarget.reference == "nginx", "first pull target preserves wave order")
            expect(firstTarget.platform == "linux/amd64", "pull target captures platform flag")
        } else {
            expect(false, "first pull target is missing")
        }
    }

    private mutating func runImagePullRuntimeProgressInsertionTests() {
        let plan = ServicePlan(
            serviceName: "web",
            name: "demo_web_progress_insert",
            projectName: "demo",
            image: "nginx",
            runArguments: ["run", "-d", "nginx", "--progress"]
        )
        defer {
            ComposeFileStaging.removeContainerStaging(
                projectName: plan.projectName,
                containerName: plan.name
            )
        }
        do {
            let arguments = try ComposeFileStaging.preparedRunArguments(
                for: plan,
                imagePullOutput: .headlessHost
            )
            let imageIndex = arguments.firstIndex(of: "nginx")
            let progressFlags = arguments.enumerated().filter { $0.element == "--progress" }
            expect(progressFlags.count == 1, "runtime progress flag is inserted exactly once")
            let progressIndex = progressFlags.first?.offset
            expect(progressIndex != nil && imageIndex != nil, "runtime progress flag is inserted")
            if let progressIndex, let imageIndex {
                expect(progressIndex < imageIndex, "runtime progress flag is inserted before image token")
                let valueIndex = progressIndex + 1
                expect(valueIndex < arguments.count, "runtime progress flag has a value")
                if valueIndex < arguments.count {
                    expect(arguments[valueIndex] == "none", "runtime progress flag disables upstream bar")
                }
            }
        } catch {
            fputs("FAIL: unexpected progress insertion error: \(error)\n", stderr)
            failures += 1
        }
    }

    private mutating func runImagePullRuntimeProgressGuardTests() {
        let plan = ServicePlan(
            serviceName: "web",
            name: "demo_web_progress_guard",
            projectName: "demo",
            image: "nginx",
            runArguments: ["run", "-d", "--progress", "plain", "nginx"]
        )
        defer {
            ComposeFileStaging.removeContainerStaging(
                projectName: plan.projectName,
                containerName: plan.name
            )
        }
        do {
            let arguments = try ComposeFileStaging.preparedRunArguments(
                for: plan,
                imagePullOutput: .headlessHost
            )
            let progressFlags = arguments.enumerated().filter { $0.element == "--progress" }
            expect(progressFlags.count == 1, "existing runtime progress flag is not duplicated")
            if let progressIndex = progressFlags.first?.offset {
                let valueIndex = progressIndex + 1
                expect(valueIndex < arguments.count, "existing runtime progress flag has a value")
                if valueIndex < arguments.count {
                    expect(arguments[valueIndex] == "plain", "existing runtime progress flag is preserved")
                }
            }
        } catch {
            fputs("FAIL: unexpected progress guard error: \(error)\n", stderr)
            failures += 1
        }
    }
}
