import ComposeCore

extension TestRunner {
    mutating func runCpTests() {
        runCpPathTests()
        runCpResolverTests()
        runCpSessionTests()
    }
}
