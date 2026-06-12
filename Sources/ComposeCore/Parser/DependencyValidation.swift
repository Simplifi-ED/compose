import Foundation

package enum DependencyValidation {
    package static func validate(services: [String: ComposeService]) throws {
        for (serviceName, service) in services {
            for dependency in service.dependsOn where dependency.condition == .serviceHealthy {
                guard let dependencyService = services[dependency.service] else {
                    continue
                }
                guard dependencyService.healthcheck != nil else {
                    throw ComposeError.invalidField(
                        "depends_on",
                        reason:
                            "service '\(serviceName)' depends on '\(dependency.service)' "
                            + "with condition service_healthy, but '\(dependency.service)' has no healthcheck."
                    )
                }
            }
        }
    }

    package static func validateMachineMode(
        services: [String: ComposeService],
        machineName: String?
    ) throws {
        guard machineName != nil else { return }
        for service in services.values {
            for dependency in service.dependsOn where dependency.condition == .serviceCompletedSuccessfully {
                throw ComposeError.machineUnsupportedOperation(
                    "depends_on condition service_completed_successfully"
                )
            }
        }
    }
}
