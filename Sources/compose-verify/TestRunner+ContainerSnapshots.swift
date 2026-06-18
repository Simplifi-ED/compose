import ComposeCore
import ContainerAPIClient
import ContainerResource
import ContainerizationOCI
import ContainerizationOS
import Foundation

extension TestRunner {
    static func makeContainerSnapshot(
        project: String,
        service: String,
        status: RuntimeStatus,
        id: String? = nil,
        extraLabels: [String: String] = [:]
    ) -> ContainerSnapshot {
        let containerID = id ?? "\(project)_\(service)_1"
        let image = ImageDescription(
            reference: "docker.io/library/alpine:latest",
            descriptor: Descriptor(
                mediaType: "application/vnd.oci.image.manifest.v1+json",
                digest: "sha256:" + String(repeating: "0", count: 64),
                size: 0
            )
        )
        let process = ProcessConfiguration(
            executable: "/bin/sh",
            arguments: [],
            environment: [],
            user: .raw(userString: "root")
        )
        var configuration = ContainerConfiguration(id: containerID, image: image, process: process)
        configuration.labels = [
            ComposeLabels.project: project,
            ComposeLabels.service: service
        ]
        for (key, value) in extraLabels {
            configuration.labels[key] = value
        }
        return ContainerSnapshot(
            configuration: configuration,
            status: status,
            networks: []
        )
    }
}
