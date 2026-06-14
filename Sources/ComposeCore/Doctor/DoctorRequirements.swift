import Foundation

package enum DoctorRequirements {
    package static let minimumContainerVersion = "1.0.0"
    package static let probeImageReference = "docker.io/library/busybox:1.36.1"
    package static let probeImageTag = "1.36.1"

    /// Warn when free space falls below this threshold.
    package static let diskWarnThresholdBytes: Int64 = 2 * 1024 * 1024 * 1024
    /// Fail when free space falls below this threshold.
    package static let diskFailThresholdBytes: Int64 = 500 * 1024 * 1024

    package static let subprocessTimeout: Duration = .seconds(30)
    package static let kernelProbeTimeout: Duration = .seconds(60)
}
