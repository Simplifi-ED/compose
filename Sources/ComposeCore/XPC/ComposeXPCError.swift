import Foundation

package enum ComposeXPCErrorCode: Int {
    case clientNotAllowed = 1
    case invalidRequest = 2
    case invalidPath = 3
    case encodingFailed = 4
    case operationFailed = 5
}

package enum ComposeXPCError {
    package static func nsError(code: ComposeXPCErrorCode, message: String) -> NSError {
        NSError(
            domain: ComposeXPCConstants.errorDomain,
            code: code.rawValue,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    package static func clientNotAllowed(_ detail: String) -> NSError {
        nsError(
            code: .clientNotAllowed,
            message: "Client not allowed: \(detail)"
        )
    }

    package static func invalidPath(_ detail: String) -> NSError {
        nsError(code: .invalidPath, message: detail)
    }

    package static func invalidRequest(_ detail: String) -> NSError {
        nsError(code: .invalidRequest, message: detail)
    }
}
