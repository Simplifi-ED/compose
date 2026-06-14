import Foundation

package enum DoctorChecks {
    package static func run(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        runtimeDependencies: DoctorRuntimeDependencies? = nil
    ) async -> [DoctorFinding] {
        let runtimeDeps = runtimeDependencies ?? DoctorRuntimeDependencies(environment: environment)

        let containerCLIPath = await runtimeDeps.whichExecutable("container", environment)
        let pluginPath = PluginInstallPath.resolve(
            containerCLIPath: containerCLIPath,
            environment: environment
        )
        async let environmentFindings = DoctorChecksEnvironment.runParallel(
            containerCLIPath: containerCLIPath,
            pluginPath: pluginPath
        )
        async let runtimeFindings = DoctorChecksRuntime.run(
            containerCLIPath: containerCLIPath,
            dependencies: runtimeDeps
        )

        let env = await environmentFindings
        let runtime = await runtimeFindings
        return env + runtime
    }
}
