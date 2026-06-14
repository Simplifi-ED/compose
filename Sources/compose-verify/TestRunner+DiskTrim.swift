import ComposeCore
import Foundation

extension TestRunner {
    mutating func runDiskTrimTests() {
        runDiskTrimHostTests()
        runDiskTrimDryRunTests()
    }

    private mutating func runDiskTrimHostTests() {
        expect(DiskTrimHost.isAPFS(path: "/"), "APFS gate accepts root on macOS dev host")
        expect(
            DiskTrimHost.trimHelperImage == "docker.io/library/busybox:1.36.1",
            "trim helper image is pinned"
        )
        let rootfs = DiskTrimHost.containerRootfsPath(
            containerID: "demo_web_1",
            appRoot: DiskTrimHost.defaultAppRoot()
        )
        expect(rootfs.hasSuffix("containers/demo_web_1/rootfs.ext4"), "container rootfs path layout")
    }

    private mutating func runDiskTrimDryRunTests() {
        expect(
            DryRunManifestFormatting.formatDiskTrimContainer(name: "demo_web_1")
                == "[DRY-RUN] trim container root filesystem \"demo_web_1\" (guest fstrim)",
            "dry-run container trim line"
        )
        expect(
            DryRunManifestFormatting.formatDiskTrimVolume(name: "demo_mydata")
                == "[DRY-RUN] trim named volume \"demo_mydata\" (guest fstrim)",
            "dry-run volume trim line"
        )
        expect(
            DryRunManifestFormatting.formatDiskTrimMachine(name: "dev")
                == "[DRY-RUN] trim machine guest filesystem machine=\"dev\" (guest fstrim)",
            "dry-run machine trim line"
        )

        let lines = blockingAwait {
            let manifest = DryRunManifest(machineName: "dev")
            await manifest.recordDiskTrims(
                containerNames: ["demo_web_1"],
                volumeNames: ["demo_mydata"],
                machineName: "dev"
            )
            return await manifest.sortedLines()
        }
        expect(lines.count == 3, "dry-run trim records container, volume, and machine")
        expect(
            lines.contains(
                "[DRY-RUN] machine=dev trim container root filesystem \"demo_web_1\" (guest fstrim)"
            ),
            "dry-run manifest includes machine-prefixed container trim"
        )
    }
}
