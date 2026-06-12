import ComposeCore
import Foundation

extension TestRunner {
    mutating func runIncludeTests() throws {
        try runIncludeTreeTests()
        try runIncludeDeepChainTests()
        try runIncludeEnvTests()
        try runIncludeShortSyntaxEnvTests()
        try runIncludeMultiPathMergeTests()
        try runIncludeProjectDirectoryTests()
        try runIncludeErrorTests()
    }

    mutating func runIncludeTreeTests() throws {
        let rootURL = Self.fixtureURL("include-fixture/root.yml")
        let parsed = try ComposeParser.parse(fileURL: rootURL, processEnvironment: [:])

        expect(parsed.services.count == 4, "include tree merges local and included services")
        expect(parsed.services["db"]?.image == "docker.io/library/postgres:16", "include tree merges db from common/base")
        expect(parsed.services["web"]?.ports == ["8080:80"], "include tree merges web from fragments/web")
        expect(parsed.services["app"]?.dependsOn.serviceNames == ["web", "db"], "include tree keeps local depends_on")
    }

    mutating func runIncludeDeepChainTests() throws {
        let rootURL = Self.fixtureURL("include-fixture/deep/level1.yml")
        let parsed = try ComposeParser.parse(fileURL: rootURL, processEnvironment: [:])

        expect(parsed.services.count == 4, "deep include chain merges services from nested includes")
        expect(parsed.services["db"]?.image == "docker.io/library/postgres:16", "deep chain reaches common/base")
        expect(parsed.services["gateway"]?.dependsOn.serviceNames == ["db"], "deep chain keeps gateway depends_on")
    }

    mutating func runIncludeEnvTests() throws {
        let rootURL = Self.fixtureURL("include-fixture/env-nested/parent.yml")
        let parsed = try ComposeParser.parse(fileURL: rootURL, processEnvironment: [:])

        expect(
            parsed.services["parent"]?.image == "docker.io/library/alpine:latest",
            "parent service uses .env beside parent compose file"
        )
        expect(
            parsed.services["child"]?.image == "docker.io/library/alpine:3.18",
            "included child uses env_file from include entry"
        )

        let shellOverride = try ComposeParser.parse(
            fileURL: rootURL,
            processEnvironment: ["CHILD_IMAGE": "docker.io/library/alpine:latest"]
        )
        expect(
            shellOverride.services["child"]?.image == "docker.io/library/alpine:latest",
            "shell environment overrides included env_file values"
        )
    }

    mutating func runIncludeShortSyntaxEnvTests() throws {
        let rootURL = Self.fixtureURL("include-fixture/env-short-syntax/parent.yml")
        let parsed = try ComposeParser.parse(fileURL: rootURL, processEnvironment: [:])
        expect(
            parsed.services["child"]?.image == "docker.io/library/alpine:3.18",
            "short-syntax include loads default .env from including file directory"
        )
    }

    mutating func runIncludeMultiPathMergeTests() throws {
        let rootURL = Self.fixtureURL("include-fixture/multi-path/parent.yml")
        let parsed = try ComposeParser.parse(fileURL: rootURL, processEnvironment: [:])
        let web = parsed.services["web"]
        expect(web?.image == "docker.io/library/alpine:latest", "multi-path include merges later file over earlier")
        expect(web?.command == .string("sleep 300"), "multi-path include merges command from override file")
    }

    mutating func runIncludeProjectDirectoryTests() throws {
        let rootURL = Self.fixtureURL("include-fixture/project-dir/parent.yml")
        let parsed = try ComposeParser.parse(fileURL: rootURL, processEnvironment: [:])
        guard let worker = parsed.services["worker"] else {
            expect(false, "project-dir fixture defines worker service")
            return
        }
        let childDirectory = Self.fixtureURL("include-fixture/project-dir/child").standardizedFileURL

        expect(
            worker.projectDirectory == childDirectory,
            "included service stamps project_directory from include entry"
        )

        let volumeFlag = try ServicePlanner.volumeFlag(
            for: worker.volumes[0],
            relativeTo: worker.projectDirectory(orDefault: rootURL.deletingLastPathComponent()),
            projectName: "demo"
        )
        let expectedData = childDirectory.appendingPathComponent("data").standardizedFileURL.path
        expect(volumeFlag == "\(expectedData):/mnt/data", "relative volume resolves against included project_directory")
    }

    mutating func runIncludeErrorTests() throws {
        expectComposeError(
            "circular include between two files",
            matching: { if case .circularInclude = $0 { true } else { false } },
            body: {
                _ = try ComposeParser.parse(fileURL: Self.fixtureURL("include-fixture/loop-a.yml"))
            }
        )

        expectComposeError(
            "circular include with relative path aliases",
            matching: { if case .circularInclude = $0 { true } else { false } },
            body: {
                _ = try ComposeParser.parse(fileURL: Self.fixtureURL("include-fixture/loop-relative-a.yml"))
            }
        )

        expectComposeError(
            "self include",
            matching: { if case .circularInclude = $0 { true } else { false } },
            body: {
                _ = try ComposeParser.parse(fileURL: Self.fixtureURL("include-fixture/self-include.yml"))
            }
        )

        expectComposeError(
            "missing included file",
            matching: { if case .fileNotFound = $0 { true } else { false } },
            body: {
                _ = try ComposeParser.parse(fileURL: Self.fixtureURL("include-fixture/missing-child.yml"))
            }
        )

        expectComposeError(
            "local service conflicts with included service",
            matching: { if case .includeConflict(let service, _, _) = $0 { service == "web" } else { false } },
            body: {
                _ = try ComposeParser.parse(fileURL: Self.fixtureURL("include-fixture/conflict-local.yml"))
            }
        )

        expectComposeError(
            "included services conflict across include entries",
            matching: { if case .includeConflict(let service, _, _) = $0 { service == "shared" } else { false } },
            body: {
                _ = try ComposeParser.parse(fileURL: Self.fixtureURL("include-fixture/conflict-across-includes.yml"))
            }
        )

        try runIncludeResourceConflictTests()
    }

    mutating func runIncludeResourceConflictTests() throws {
        expectComposeError(
            "included secret conflicts with parent secret",
            matching: {
                if case .includeResourceConflict(let name, .secret, _, _) = $0 {
                    return name == "shared_secret"
                }
                return false
            },
            body: {
                _ = try ComposeParser.parse(
                    fileURL: Self.fixtureURL("include-fixture/resource-conflict-secret.yml")
                )
            }
        )

        expectComposeError(
            "included config conflicts with parent config",
            matching: {
                if case .includeResourceConflict(let name, .config, _, _) = $0 {
                    return name == "shared_config"
                }
                return false
            },
            body: {
                _ = try ComposeParser.parse(
                    fileURL: Self.fixtureURL("include-fixture/resource-conflict-config.yml")
                )
            }
        )

        expectComposeError(
            "included volume conflicts with parent volume",
            matching: {
                if case .includeVolumeConflict(let name, _, _) = $0 {
                    return name == "shared_volume"
                }
                return false
            },
            body: {
                _ = try ComposeParser.parse(
                    fileURL: Self.fixtureURL("include-fixture/resource-conflict-volume.yml")
                )
            }
        )
    }
}
