import Foundation

extension BuildRunner {
    package static func resolvedDockerfilePath(for plan: Plan) throws -> String? {
        try BuildValidator.resolvedDockerfileURL(
            dockerfile: plan.dockerfile,
            contextURL: plan.contextURL,
            serviceName: plan.serviceName
        )?.path
    }

    package static func buildArguments(for plan: Plan, progress: ProgressSetting?) throws -> [String] {
        var arguments: [String] = ["-t", plan.tag]
        if let dockerfilePath = try resolvedDockerfilePath(for: plan) {
            arguments.append(contentsOf: ["-f", dockerfilePath])
        }
        for key in plan.args.keys.sorted() {
            guard let value = plan.args[key] else { continue }
            arguments.append(contentsOf: ["--build-arg", "\(key)=\(value)"])
        }
        if let target = plan.target, !target.isEmpty {
            arguments.append(contentsOf: ["--target", target])
        }
        if let progress {
            switch progress {
            case .auto:
                arguments.append(contentsOf: ["--progress", "auto"])
            case .plain:
                arguments.append(contentsOf: ["--progress", "plain"])
            case .none:
                arguments.append("--quiet")
            }
        }
        arguments.append(plan.contextURL.path)
        return arguments
    }
}
