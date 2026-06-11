import ArgumentParser
import Foundation

public struct ProjectOptions: ParsableArguments {
    public init() {}

    @Option(
        name: .shortAndLong,
        help: """
        Path to a compose file. Repeat to merge; later files override earlier ones. \
        When omitted, discovers compose.yaml (or docker-compose.yml) and optional override files; \
        COMPOSE_FILE overrides discovery when set.
        """
    )
    var files: [String] = []

    @Option(
        name: .shortAndLong,
        help: """
        Project name used for container naming. Precedence: -p, COMPOSE_PROJECT_NAME, \
        compose file name:, then the first compose file's parent directory.
        """
    )
    var projectName: String?

    var hasExplicitProjectName: Bool {
        guard let projectName else { return false }
        return !projectName.isEmpty
    }

    func effectiveFiles() throws -> [String] {
        try ComposeFileResolution.discover(cliFiles: files)
    }

    func resolvedFileURLs() throws -> [URL] {
        try ComposeFileResolution.resolved(files: effectiveFiles())
    }

    /// Returns compose files when they exist. When only the default filename is requested and absent,
    /// returns nil so `down -p` can tear down by project name alone. Any other missing path throws.
    func resolvedFileURLsIfPresent() throws -> [URL]? {
        try ComposeFileResolution.resolvedIfPresent(files: effectiveFiles())
    }

    func resolvedProjectName(composeFile: ComposeFile? = nil, fileURL: URL? = nil) throws -> String {
        try ProjectNameResolver.resolve(
            cliProjectName: projectName,
            composeName: composeFile?.name,
            firstFileURL: fileURL
        )
    }

    /// Resolved project name and optional compose file for label-based commands (`down`, `ps`).
    ///
    /// When `skipComposeFileOnExplicitProject` is true and `-p` is set, compose files are not
    /// discovered or parsed so broken YAML in the working directory cannot block the command.
    package struct LabelCommandContext: Sendable {
        package let projectName: String
        package let composeFile: ComposeFile?
        package let fileURLs: [URL]?

        package init(projectName: String, composeFile: ComposeFile?, fileURLs: [URL]?) {
            self.projectName = projectName
            self.composeFile = composeFile
            self.fileURLs = fileURLs
        }
    }

    package func resolvedLabelCommandContext(
        skipComposeFileOnExplicitProject: Bool = false,
        profileFilterRequested: Bool = false
    ) throws -> LabelCommandContext {
        if skipComposeFileOnExplicitProject, hasExplicitProjectName, !profileFilterRequested {
            let projectName = try resolvedProjectName()
            return LabelCommandContext(projectName: projectName, composeFile: nil, fileURLs: nil)
        }

        let fileURLs = try resolvedFileURLsIfPresent()
        let composeFile: ComposeFile?
        if let fileURLs {
            composeFile = try ComposeParser.parseForShutdown(fileURLs: fileURLs)
        } else {
            composeFile = nil
        }
        let projectName = try resolvedProjectName(composeFile: composeFile, fileURL: fileURLs?.first)
        return LabelCommandContext(
            projectName: projectName,
            composeFile: composeFile,
            fileURLs: fileURLs
        )
    }

    package func resolvedQueryServiceFilter(
        context: LabelCommandContext,
        profileOptions: ProfileOptions,
        positionalServices: [String]
    ) throws -> Set<String>? {
        try ProfileFilter.queryServiceFilter(
            composeFile: context.composeFile,
            activeProfiles: profileOptions.activeProfileSet,
            positionalServices: positionalServices,
            profileFilterRequested: profileOptions.profileFilterRequested
        )
    }
}
