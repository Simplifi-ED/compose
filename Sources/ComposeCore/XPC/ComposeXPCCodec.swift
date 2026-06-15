import Foundation

package enum ComposeXPCCodec {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder = JSONDecoder()

    package static func encode<T: Encodable>(_ value: T) throws -> String {
        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw ComposeXPCError.nsError(code: .encodingFailed, message: "Response could not be encoded as UTF-8.")
        }
        return string
    }

    package static func decodeRequest(_ json: String) throws -> ComposeXPCProjectRequest {
        guard let data = json.data(using: .utf8) else {
            throw ComposeXPCError.invalidRequest("Request body is not valid UTF-8.")
        }
        do {
            return try decoder.decode(ComposeXPCProjectRequest.self, from: data)
        } catch {
            throw ComposeXPCError.invalidRequest("Request JSON is invalid: \(error.localizedDescription)")
        }
    }

    package static func errorResponseJSON(from error: Error) -> String {
        let nsError = error as NSError
        let response = ComposeXPCErrorResponse(
            code: nsError.code,
            message: nsError.localizedDescription
        )
        return (try? encode(response)) ?? "{\"code\":\(nsError.code),\"message\":\"Operation failed.\"}"
    }
}
