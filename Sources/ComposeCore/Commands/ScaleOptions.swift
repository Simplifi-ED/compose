import ArgumentParser

public struct ScaleOptions: ParsableArguments {
    public init() {}

    @Option(
        name: .customLong("scale"),
        help: """
        Number of containers to run for a service, as SERVICE=COUNT (for example web=3). \
        Repeat for multiple services. Overrides deploy.replicas in the compose file.
        """
    )
    var scale: [String] = []

    /// Parses repeated `SERVICE=COUNT` entries; later entries win for the same service.
    public func resolvedScaleOverrides() throws -> [String: Int] {
        var overrides: [String: Int] = [:]
        for entry in scale {
            guard let separatorIndex = entry.firstIndex(of: "=") else {
                throw ComposeError.invalidScaleSpec(entry)
            }
            let service = String(entry[..<separatorIndex])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let countText = String(entry[entry.index(after: separatorIndex)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !service.isEmpty, let count = Int(countText), count >= 1 else {
                throw ComposeError.invalidScaleSpec(entry)
            }
            overrides[service] = count
        }
        return overrides
    }
}
