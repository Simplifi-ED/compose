import ArgumentParser

public struct WorkspaceHygieneOptions: ParsableArguments {
    public init() {}

    @Flag(
        name: .long,
        help: """
        Remove containers for services not in the compose file or not started by the current profile set.
        """
    )
    var removeOrphans = false

    public var shouldRemoveOrphans: Bool { removeOrphans }
}
