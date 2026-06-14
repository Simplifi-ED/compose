import Foundation

package enum DoctorReport {
    package struct Summary: Equatable, Sendable {
        package let passed: Int
        package let warnings: Int
        package let critical: Int
        package let skipped: Int
    }

    package static func summary(for findings: [DoctorFinding]) -> Summary {
        var passed = 0
        var warnings = 0
        var critical = 0
        var skipped = 0
        for finding in findings {
            switch finding.status {
            case .pass:
                passed += 1
            case .warn:
                warnings += 1
            case .fail where finding.severity == .critical:
                critical += 1
            case .fail:
                warnings += 1
            case .skipped:
                skipped += 1
            }
        }
        return Summary(passed: passed, warnings: warnings, critical: critical, skipped: skipped)
    }

    package static func summaryLine(for findings: [DoctorFinding]) -> String {
        let counts = summary(for: findings)
        return """
        Summary: \(counts.passed) passed, \(counts.warnings) warnings, \
        \(counts.critical) critical, \(counts.skipped) skipped
        """.replacingOccurrences(of: "\n", with: "")
    }

    package static func hasCriticalFailure(_ findings: [DoctorFinding]) -> Bool {
        findings.contains { $0.status == .fail && $0.severity == .critical }
    }

    package static func lines(
        for findings: [DoctorFinding],
        mode: TerminalMode
    ) -> [String] {
        var output: [String] = []
        for finding in findings.sorted(by: { $0.id < $1.id }) {
            output.append(statusPrefix(for: finding.status, mode: mode) + " " + finding.title)
            output.append("   " + finding.detail)
            if let remediation = finding.remediation {
                for line in remediation.split(whereSeparator: \.isNewline) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("#") {
                        output.append("   \(trimmed)")
                    } else if !trimmed.isEmpty {
                        output.append("   → \(trimmed)")
                    }
                }
            }
            output.append("")
        }
        output.append(summaryLine(for: findings))
        return output
    }

    private static func statusPrefix(for status: DoctorStatus, mode: TerminalMode) -> String {
        switch (status, mode) {
        case (.pass, .interactive):
            "✅"
        case (.warn, .interactive):
            "⚠️"
        case (.fail, .interactive):
            "❌"
        case (.skipped, .interactive):
            "⏭"
        case (.pass, .plain), (.pass, .pipe):
            "OK"
        case (.warn, .plain), (.warn, .pipe):
            "WARN"
        case (.fail, .plain), (.fail, .pipe):
            "FAIL"
        case (.skipped, .plain), (.skipped, .pipe):
            "SKIP"
        }
    }
}
