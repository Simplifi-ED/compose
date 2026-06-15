import Foundation

package enum ComposeXPCHandlers {
    package static func inputs(from request: ComposeXPCProjectRequest) -> ComposeCommandInputs {
        ComposeCommandInputs(
            files: request.files,
            projectName: request.projectName,
            profiles: request.profiles,
            machineName: request.machineName,
            positionalServices: request.services
        )
    }

    package static func statusJSON(_ requestJSON: String) async throws -> String {
        let request = try ComposeXPCCodec.decodeRequest(requestJSON)
        let result = try await ProjectListRun.run(
            ProjectListRequest(inputs: inputs(from: request))
        )
        return try ComposeXPCCodec.encode(ComposeXPCDTOMapping.statusResponse(from: result))
    }

    package static func mutationJSON(
        _ requestJSON: String,
        operation: MutationOperation
    ) async throws -> String {
        let request = try ComposeXPCCodec.decodeRequest(requestJSON)
        let inputs = inputs(from: request)
        if operation == .startup {
            try validateStartupRequest(request)
        }
        let result: ProjectMutationResult
        switch operation {
        case .startup:
            result = try await ProjectUpRun.run(
                ProjectUpRequest(
                    inputs: inputs,
                    dryRun: request.dryRun,
                    removeOrphans: request.removeOrphans
                )
            )
        case .shutdown:
            result = try await ProjectDownRun.run(
                ProjectDownRequest(
                    inputs: inputs,
                    dryRun: request.dryRun,
                    removeVolumes: request.removeVolumes
                )
            )
        }
        return try ComposeXPCCodec.encode(ComposeXPCDTOMapping.mutationResponse(from: result))
    }

    package enum MutationOperation: Sendable {
        case startup
        case shutdown
    }

    private static func validateStartupRequest(_ request: ComposeXPCProjectRequest) throws {
        try ComposePathValidation.validateComposeFilePaths(request.files)
        guard !request.files.isEmpty else {
            throw ComposeXPCError.invalidRequest(
                "up requires at least one compose file path in files[] (the listener has no project working directory)."
            )
        }
    }
}
