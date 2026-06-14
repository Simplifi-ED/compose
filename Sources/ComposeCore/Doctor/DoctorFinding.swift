import Foundation

package enum DoctorStatus: String, Codable, Sendable {
    case pass
    case warn
    case fail
    case skipped
}

package enum DoctorSeverity: String, Codable, Sendable {
    case critical
    case advisory
}

package struct DoctorFinding: Codable, Sendable, Equatable {
    package let id: String
    package let title: String
    package let detail: String
    package let remediation: String?
    package let status: DoctorStatus
    package let severity: DoctorSeverity

    package init(
        id: String,
        title: String,
        detail: String,
        remediation: String? = nil,
        status: DoctorStatus,
        severity: DoctorSeverity
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.remediation = remediation
        self.status = status
        self.severity = severity
    }
}
