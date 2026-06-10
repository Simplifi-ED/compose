import Foundation
import Yams

public enum ComposeParser {
    public static func parse(fileURL: URL) throws -> ComposeFile {
        let path = fileURL.path
        guard FileManager.default.fileExists(atPath: path) else {
            throw ComposeError.fileNotFound(path)
        }

        let contents: String
        do {
            contents = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            throw ComposeError.readFailed(path, underlying: error)
        }

        let composeFile: ComposeFile
        do {
            composeFile = try YAMLDecoder().decode(ComposeFile.self, from: contents)
        } catch {
            throw ComposeError.parseFailed(path, underlying: error)
        }

        try validate(composeFile)
        return composeFile
    }

    static func validate(_ composeFile: ComposeFile) throws {
        guard !composeFile.services.isEmpty else {
            throw ComposeError.noServices
        }

        for (serviceName, service) in composeFile.services {
            guard let image = service.image, !image.isEmpty else {
                throw ComposeError.missingImage(service: serviceName)
            }
        }
    }
}
