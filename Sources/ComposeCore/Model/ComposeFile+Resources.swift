import Foundation

extension ComposeFile {
    package func resources(for kind: ComposeFileMountKind) -> [String: ComposeFileResource] {
        switch kind {
        case .config: configs
        case .secret: secrets
        }
    }
}

extension ComposeService {
    package func mounts(for kind: ComposeFileMountKind) -> [ComposeServiceMount] {
        switch kind {
        case .config: configs
        case .secret: secrets
        }
    }
}
