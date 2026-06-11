import Foundation
import Yams

/// Canonical YAML export for resolved compose models.
public enum ComposeSerializer {
    public static func yamlString(from composeFile: ComposeFile) throws -> String {
        let encoder = YAMLEncoder()
        let yaml = try encoder.encode(composeFile)
        if yaml.hasSuffix("\n") {
            return yaml
        }
        return yaml + "\n"
    }
}
