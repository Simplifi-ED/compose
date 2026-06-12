import ComposeCore
import Foundation

extension TestRunner {
    mutating func runCpPathTests() {
        runCpPathRefTests()
        runCpPathValidatorTests()
    }

    private mutating func runCpPathRefTests() {
        do {
            let serviceRef = try CpPathRef.parse("web:/app/data.txt")
            guard case .service(name: "web", path: "/app/data.txt") = serviceRef else {
                fputs("FAIL: expected service path ref\n", stderr)
                failures += 1
                return
            }
            expect(true, "service path ref parses")
        } catch {
            fputs("FAIL: service path ref should parse: \(error)\n", stderr)
            failures += 1
        }

        do {
            let localRef = try CpPathRef.parse("/tmp/out.txt")
            guard case .local("/tmp/out.txt") = localRef else {
                fputs("FAIL: expected local path ref\n", stderr)
                failures += 1
                return
            }
            expect(true, "absolute local path ref parses")
        } catch {
            fputs("FAIL: local path ref should parse: \(error)\n", stderr)
            failures += 1
        }

        expectComposeError(
            "relative container path rejected",
            matching: { if case .invalidCpPath = $0 { true } else { false } },
            body: { _ = try CpPathRef.parse("web:app/data.txt") }
        )

        expectComposeError(
            "empty service name rejected",
            matching: { if case .invalidCpPath = $0 { true } else { false } },
            body: { _ = try CpPathRef.parse(":/app/data.txt") }
        )
    }

    private mutating func runCpPathValidatorTests() {
        expectComposeError(
            "container path rejects dot-dot",
            matching: { if case .invalidCpPath = $0 { true } else { false } },
            body: { _ = try CpPathValidator.validateContainerPath("/app/../etc/passwd") }
        )

        let cwd = FileManager.default.currentDirectoryPath
        let inside = (cwd as NSString).appendingPathComponent("cp-validator-inside-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(atPath: inside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: inside) }

        let insideFile = (inside as NSString).appendingPathComponent("file.txt")
        FileManager.default.createFile(atPath: insideFile, contents: Data("ok".utf8))

        do {
            let resolved = try CpPathValidator.resolveHostPath(insideFile, role: .source)
            expect(resolved.path == (insideFile as NSString).standardizingPath, "host source resolves inside cwd")
        } catch {
            fputs("FAIL: host source inside cwd should resolve: \(error)\n", stderr)
            failures += 1
        }

        expectComposeError(
            "host path outside cwd rejected",
            matching: { if case .cpHostPathOutsideCWD = $0 { true } else { false } },
            body: {
                _ = try CpPathValidator.resolveHostPath("../outside-cp-\(UUID().uuidString)", role: .destination)
            }
        )

        expectComposeError(
            "missing host source rejected",
            matching: { if case .cpSourceNotFound = $0 { true } else { false } },
            body: {
                _ = try CpPathValidator.resolveHostPath("missing-cp-\(UUID().uuidString)", role: .source)
            }
        )
    }
}
