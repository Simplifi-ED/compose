import Foundation

enum DependencyValidation {
  static func validate(services: [String: ComposeService]) throws {
    for (serviceName, service) in services {
      for dependency in service.dependsOn where dependency.condition == .serviceHealthy {
        guard let dependencyService = services[dependency.service] else {
          continue
        }
        guard dependencyService.healthcheck != nil else {
          throw ComposeError.invalidField(
            "depends_on",
            reason:
              "service '\(serviceName)' depends on '\(dependency.service)' with condition service_healthy, "
              + "but '\(dependency.service)' has no healthcheck."
          )
        }
      }
    }
  }
}
