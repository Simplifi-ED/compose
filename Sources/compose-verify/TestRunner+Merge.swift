import ComposeCore
import Foundation

extension TestRunner {
    mutating func runMergeTests() throws {
        let mergeDirectory = Self.fixtureURL("merge/base.yml").deletingLastPathComponent()
        let baseURL = mergeDirectory.appendingPathComponent("base.yml")
        let overrideURL = mergeDirectory.appendingPathComponent("override.yml")

        let merged = try ComposeParser.parse(fileURLs: [baseURL, overrideURL])

        expect(merged.name == "override-project", "merge top-level name from last file")
        expect(merged.services["worker"]?.image == "docker.io/library/alpine:3.18", "merge preserves base-only service")
        expect(merged.services["debug"]?.image == "docker.io/library/alpine:latest", "merge adds override-only service")

        let web = merged.services["web"]
        expect(web?.image == "docker.io/library/alpine:latest", "merge overrides scalar image")
        expect(web?.command == .string("sleep 300"), "merge keeps base command when override omits it")
        expect(web?.ports == ["18080:80", "18081:81"], "merge appends ports")
        expect(
            web?.environment == .map(["FOO": "base", "SHARED": "from-override", "BAR": "override-only"]),
            "merge environment map keys"
        )
        expect(web?.dependsOn == ["db", "cache"], "merge appends depends_on")

        let commandOverrideURL = mergeDirectory.appendingPathComponent("override-command.yml")
        let commandMerged = try ComposeParser.parse(fileURLs: [baseURL, commandOverrideURL])
        expect(
            commandMerged.services["web"]?.command == .list(["sleep", "999"]),
            "merge command scalar override replaces form"
        )

        let partialOverrideURL = mergeDirectory.appendingPathComponent("override-partial.yml")
        let partialMerged = try ComposeParser.parse(fileURLs: [baseURL, partialOverrideURL])
        let partialWeb = partialMerged.services["web"]
        expect(partialWeb?.image == "docker.io/library/alpine:3.18", "merge partial override keeps base image")
        expect(
            partialWeb?.environment == .map(["FOO": "base", "SHARED": "from-base", "PARTIAL": "added"]),
            "merge partial override environment"
        )

        let baseListURL = mergeDirectory.appendingPathComponent("base-list-env.yml")
        let overrideListURL = mergeDirectory.appendingPathComponent("override-list-env.yml")
        let listMerged = try ComposeParser.parse(fileURLs: [baseListURL, overrideListURL])
        expect(
            listMerged.services["web"]?.environment == .list(["FOO=base-list", "BAR=override-list"]),
            "merge appends environment list"
        )

        expectComposeError(
            "missing second compose file",
            matching: { if case .fileNotFound = $0 { true } else { false } },
            body: {
                _ = try ComposeParser.parse(fileURLs: [baseURL, mergeDirectory.appendingPathComponent("missing.yml")])
            }
        )

        let volumesOverrideURL = mergeDirectory.appendingPathComponent("override-volumes.yml")
        let volumesMerged = try ComposeParser.parse(fileURLs: [baseURL, volumesOverrideURL])
        expect(
            volumesMerged.services["web"]?.volumes == ["./config:/mnt/config", "./data:/mnt/data"],
            "merge appends volumes"
        )
        expect(volumesMerged.services["web"]?.containerName == "merged-web", "merge overrides container_name")

        let envFormURL = mergeDirectory.appendingPathComponent("override-env-form.yml")
        let envFormMerged = try ComposeParser.parse(fileURLs: [baseURL, envFormURL])
        expect(
            envFormMerged.services["web"]?.environment == .list(["REPLACED=list-form"]),
            "merge environment form mismatch last wins"
        )

        let thirdLayerURL = mergeDirectory.appendingPathComponent("third-layer.yml")
        let threeFileMerged = try ComposeParser.parse(fileURLs: [baseURL, overrideURL, thirdLayerURL])
        expect(threeFileMerged.name == "third-layer", "merge three-file chain name")
        expect(
            threeFileMerged.services["web"]?.ports == ["18080:80", "18081:81", "18082:82"],
            "merge three-file chain appends ports"
        )
    }
}
