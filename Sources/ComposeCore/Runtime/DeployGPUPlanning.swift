import Foundation

package enum DeployGPUPlanning {
    // ponytail: hard-fail until container exposes a GPU/Metal run flag; wire run-flag mapping here when upstream lands.
    package static let unsupportedReason =
        "GPU reservations require container runtime GPU/Metal passthrough support, "
        + "which is unavailable in container 1.0.0. Remove deploy.resources.reservations.devices "
        + "or upgrade once GPU support is released."

    package static func validateReservations(
        _ reservations: ComposeResourceReservations?,
        machineName: String? = nil
    ) throws {
        guard let reservations, reservations.hasContent else { return }
        let context = machineName.map { "--machine \($0)" } ?? "application sandbox"
        throw ComposeError.invalidField(
            "deploy.resources.reservations.devices",
            reason: "\(unsupportedReason) (requested for \(context))"
        )
    }
}
