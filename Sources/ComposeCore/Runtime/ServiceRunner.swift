import ContainerCommands
import Foundation

public enum ServiceRunner {
    public static func up(plans: [ServicePlan]) async throws {
        guard !plans.isEmpty else { return }

        var failures: [(service: String, error: Error)] = []

        await withTaskGroup(of: (String, Error?).self) { group in
            for plan in plans {
                group.addTask {
                    do {
                        var command = try Application.ContainerRun.parse(plan.runArguments)
                        try await command.run()
                        return (plan.serviceName, nil)
                    } catch {
                        return (plan.serviceName, error)
                    }
                }
            }

            for await result in group {
                if let error = result.1 {
                    failures.append((service: result.0, error: error))
                }
            }
        }

        if !failures.isEmpty {
            throw ComposeError.multipleServiceFailures(failures)
        }
    }

    public static func down(containerIDs: [String]) async throws {
        guard !containerIDs.isEmpty else { return }

        var failures: [(service: String, error: Error)] = []

        await withTaskGroup(of: (String, Error?).self) { group in
            for containerID in containerIDs {
                group.addTask {
                    do {
                        var command = try Application.ContainerStop.parse([containerID])
                        try await command.run()
                        return (containerID, nil)
                    } catch {
                        return (containerID, error)
                    }
                }
            }

            for await result in group {
                if let error = result.1 {
                    failures.append((service: result.0, error: error))
                }
            }
        }

        if !failures.isEmpty {
            throw ComposeError.multipleServiceFailures(failures)
        }
    }
}
