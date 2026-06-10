import ComposeCore
import Foundation

extension TestRunner {
    mutating func runTerminalTests() {
        runTerminalModeTests()
        runANSIPrefixTests()
        runTableFormatTests()
    }

    private mutating func runTerminalModeTests() {
        expect(
            TerminalMode.resolve(isTTY: true, environment: [:]) == .interactive,
            "TTY with empty environment resolves interactive"
        )
        expect(
            TerminalMode.resolve(isTTY: true, environment: ["NO_COLOR": "1"]) == .plain,
            "NO_COLOR on a TTY resolves plain"
        )
        expect(
            TerminalMode.resolve(isTTY: true, environment: ["NO_COLOR": ""]) == .interactive,
            "empty NO_COLOR does not disable color"
        )
        expect(
            TerminalMode.resolve(isTTY: true, environment: ["CI": "true"]) == .plain,
            "CI=true on a TTY resolves plain"
        )
        expect(
            TerminalMode.resolve(isTTY: true, environment: ["CI": "false"]) == .interactive,
            "CI=false resolves interactive"
        )
        expect(
            TerminalMode.resolve(isTTY: true, environment: ["CI": "0"]) == .interactive,
            "CI=0 resolves interactive"
        )
        expect(
            TerminalMode.resolve(isTTY: false, environment: [:]) == .pipe,
            "non-TTY resolves pipe"
        )
        expect(
            TerminalMode.resolve(isTTY: false, environment: ["NO_COLOR": "1"]) == .pipe,
            "non-TTY wins over NO_COLOR"
        )
        expect(
            TerminalMode.resolve(isTTY: false, environment: ["CI": "true"]) == .pipe,
            "non-TTY wins over CI"
        )
    }

    private mutating func runANSIPrefixTests() {
        let plain = ANSIPrefix.format(serviceName: "web", mode: .plain)
        expect(plain == "web     | ", "plain prefix pads name to width then pipe")

        let pipe = ANSIPrefix.format(serviceName: "web", mode: .pipe)
        expect(pipe == plain, "pipe prefix matches plain prefix")
        expect(!pipe.contains("\u{001B}["), "pipe prefix has no escape sequences")

        let interactive = ANSIPrefix.format(serviceName: "web", mode: .interactive)
        expect(interactive.contains("\u{001B}["), "interactive prefix contains escape sequence")
        expect(interactive.hasSuffix("| "), "interactive prefix ends with pipe separator")
        let strippedInteractive = stripANSI(interactive)
        expect(
            strippedInteractive == plain,
            "interactive prefix matches plain text once ANSI is stripped"
        )
        expect(
            interactive == ANSIPrefix.format(serviceName: "web", mode: .interactive),
            "same service name produces identical interactive prefix"
        )

        let index = ANSIPrefix.colorIndex(for: "web")
        expect(index == ANSIPrefix.colorIndex(for: "web"), "color index is stable")
        expect(index >= 0, "color index is non-negative")

        let names = ["web", "db", "redis", "worker", "api"]
        let distinctIndexes = Set(names.map(ANSIPrefix.colorIndex(for:)))
        expect(distinctIndexes.count > 1, "different service names spread across the palette")

        let truncated = ANSIPrefix.format(serviceName: "verylongservicename", mode: .plain)
        expect(truncated == "verylon…| ", "long service name truncates with ellipsis")

        let wide = ANSIPrefix.format(serviceName: "db", mode: .plain, width: 4)
        expect(wide == "db  | ", "custom width pads correctly")
    }

    private mutating func runTableFormatTests() {
        let table = TableFormat(columns: [
            TableFormat.Column(title: "NAME", width: 6),
            TableFormat.Column(title: "STATE", width: 7, alignment: .right)
        ])

        let row = table.formatRow(["web", "up"], mode: .plain)
        expect(row == "web          up", "row pads left and right aligned cells")

        let pipeRow = table.formatRow(["web", "up"], mode: .pipe)
        expect(pipeRow == row, "pipe row matches plain row")

        let truncatedRow = table.formatRow(["verylongname", "up"], mode: .plain)
        expect(truncatedRow.hasPrefix("veryl…"), "overlong cell truncates with ellipsis")

        let plainHeader = table.formatHeader(mode: .plain)
        expect(plainHeader == "NAME      STATE", "plain header pads column titles")
        expect(!plainHeader.contains("\u{001B}["), "plain header has no escape sequences")

        let interactiveHeader = table.formatHeader(mode: .interactive)
        expect(interactiveHeader.hasPrefix("\u{001B}[1m"), "interactive header starts bold")
        expect(interactiveHeader.hasSuffix("\u{001B}[0m"), "interactive header resets styling")
        let strippedHeader = stripANSI(interactiveHeader)
        expect(
            strippedHeader == plainHeader,
            "interactive header matches plain header once ANSI is stripped"
        )

        expect(
            TableFormat.fit("ab", width: 4, alignment: .right) == "  ab",
            "fit right-aligns short values"
        )
        expect(
            TableFormat.fit("abcdef", width: 4, alignment: .left) == "abc…",
            "fit truncates overlong values"
        )
    }

    private func stripANSI(_ string: String) -> String {
        string.replacingOccurrences(
            of: "\u{001B}\\[[0-9;]*m",
            with: "",
            options: .regularExpression
        )
    }
}
