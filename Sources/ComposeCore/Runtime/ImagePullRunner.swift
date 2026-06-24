import ContainerAPIClient
import ContainerCommands
import ContainerPersistence
import ContainerizationError
import ContainerizationOCI
import Foundation
import TerminalProgress

package struct ImagePullOutput: Sendable, Equatable {
    /// Headless host startup (XPC/API): pre-pull without stderr UI, suppress engine pull bars.
    package static let headlessHost = ImagePullOutput(display: .silent, pipeOutput: false)

    package let display: ProgressDisplay
    package let pipeOutput: Bool

    package init(display: ProgressDisplay, pipeOutput: Bool = false) {
        self.display = display
        self.pipeOutput = pipeOutput
    }

    package var suppressesRuntimeProgress: Bool { true }
}

package enum ImagePullRunner {
    private static let defaultMaxConcurrentDownloads = 3

    package static func pullMissing(
        plans: [ServicePlan],
        output: ImagePullOutput,
        maxConcurrent: Int? = nil,
        machineContext: MachineContext = .applicationSandbox
    ) async throws {
        guard !plans.isEmpty, !machineContext.isMachineMode else { return }
        let targets = pullTargets(for: plans)
        guard !targets.isEmpty else { return }

        let containerSystemConfig = try await Application.loadContainerSystemConfig()
        let missingTargets = try await targetsNeedingPull(
            targets,
            containerSystemConfig: containerSystemConfig
        )
        guard !missingTargets.isEmpty else { return }

        let progress = ImagePullProgress(
            display: output.display,
            pipeOutput: output.pipeOutput
        )
        await progress.begin(references: missingTargets.map(\.displayName))
        do {
            let items = missingTargets.map {
                ServiceRunner.ParallelRunItem(
                    label: $0.displayName,
                    collectOnSuccess: nil,
                    value: $0
                )
            }
            let result = await ServiceRunner.parallelRun(
                items,
                maxConcurrent: maxConcurrent
            ) { target in
                try Task.checkCancellation()
                try await pullAndUnpack(
                    target: target,
                    containerSystemConfig: containerSystemConfig,
                    progress: progress
                )
            }
            if result.wasInterrupted {
                throw CancellationError()
            }
            if let failure = result.failures.first {
                throw failure.error
            }
        } catch {
            await progress.finish()
            throw error
        }
        await progress.finish()
    }

    package static func pullTargets(for plans: [ServicePlan]) -> [ImagePullTarget] {
        var seen = Set<ImagePullTarget>()
        var targets: [ImagePullTarget] = []
        for plan in plans {
            let target = ImagePullTarget(
                reference: plan.image,
                platform: RunArgumentsPlatform.normalized(in: plan.runArguments)
            )
            guard !target.reference.isEmpty, !seen.contains(target) else { continue }
            seen.insert(target)
            targets.append(target)
        }
        return targets
    }

    private static func targetsNeedingPull(
        _ targets: [ImagePullTarget],
        containerSystemConfig: ContainerSystemConfig
    ) async throws -> [ImagePullTarget] {
        var missing: [ImagePullTarget] = []
        for target in targets {
            do {
                let image = try await ClientImage.get(
                    reference: target.reference,
                    containerSystemConfig: containerSystemConfig
                )
                if let platform = try target.resolvedPlatform() {
                    _ = try await image.config(for: platform)
                }
                try await image.unpack(platform: try target.resolvedPlatform())
            } catch let error as ContainerizationError where error.isCode(.notFound) {
                missing.append(target)
            }
        }
        return missing
    }

    private static func pullAndUnpack(
        target: ImagePullTarget,
        containerSystemConfig: ContainerSystemConfig,
        progress: ImagePullProgress
    ) async throws {
        let platform = try target.resolvedPlatform()
        let progressKey = target.displayName
        let handler = await progress.handler(for: progressKey)
        do {
            if let handler {
                await handler([.setDescription("Fetching image")])
            }
            let image = try await ClientImage.pull(
                reference: target.reference,
                platform: platform,
                containerSystemConfig: containerSystemConfig,
                progressUpdate: handler,
                maxConcurrentDownloads: defaultMaxConcurrentDownloads
            )
            if let handler {
                await handler([.setDescription("Unpacking image")])
            }
            try await image.unpack(platform: platform, progressUpdate: handler)
            await progress.markComplete(reference: progressKey, succeeded: true)
        } catch {
            await progress.markComplete(reference: progressKey, succeeded: false)
            throw error
        }
    }
}

package struct ImagePullTarget: Hashable, Sendable {
    package let reference: String
    package let platform: String?

    package init(reference: String, platform: String?) {
        self.reference = reference
        self.platform = platform
    }

    package func resolvedPlatform() throws -> Platform? {
        guard let platform else { return nil }
        return try Platform(from: PlatformPlanning.normalize(platform))
    }

    package var displayName: String {
        guard let platform else { return reference }
        return "\(reference) (\(platform))"
    }
}

package enum RunArgumentsPlatform {
    package static func normalized(in arguments: [String]) -> String? {
        guard let raw = DryRunManifestFormatting.parseRunArguments(arguments).platform else {
            return nil
        }
        return (try? PlatformPlanning.normalize(raw)) ?? raw
    }
}
