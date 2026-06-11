import Foundation

enum DependencyGraph {
    static func serviceLayers(for services: [String: ComposeService]) throws -> [[String]] {
        var inDegree: [String: Int] = [:]
        var dependents: [String: [String]] = [:]

        for serviceName in services.keys {
            inDegree[serviceName] = 0
            dependents[serviceName] = []
        }

        for (serviceName, service) in services {
            var seenDependencies: Set<String> = []
            let dependencies = service.dependsOn.map(\.service).filter { seenDependencies.insert($0).inserted }
            inDegree[serviceName] = dependencies.count
            for dependency in dependencies {
                guard services.keys.contains(dependency) else {
                    throw ComposeError.unknownDependency(service: serviceName, dependency: dependency)
                }
                dependents[dependency, default: []].append(serviceName)
            }
        }

        var layers: [[String]] = []
        var remaining = services.count

        while remaining > 0 {
            let layer = inDegree
                .filter { $0.value == 0 }
                .map(\.key)
                .sorted()

            guard !layer.isEmpty else {
                throw ComposeError.circularDependency(services: findCycle(in: services))
            }

            layers.append(layer)
            remaining -= layer.count

            for serviceName in layer {
                inDegree.removeValue(forKey: serviceName)
                for dependent in dependents[serviceName, default: []] {
                    inDegree[dependent, default: 0] -= 1
                }
            }
        }

        return layers
    }

    private static func findCycle(in services: [String: ComposeService]) -> [String] {
        var visited: Set<String> = []
        var stack: Set<String> = []
        var path: [String] = []

        func dfs(_ serviceName: String) -> [String]? {
            if stack.contains(serviceName) {
                if let start = path.firstIndex(of: serviceName) {
                    return Array(path[start...]) + [serviceName]
                }
                return [serviceName, serviceName]
            }
            if visited.contains(serviceName) {
                return nil
            }

            visited.insert(serviceName)
            stack.insert(serviceName)
            path.append(serviceName)

            for dependency in services[serviceName]?.dependsOn.map(\.service) ?? [] {
                if let cycle = dfs(dependency) {
                    return cycle
                }
            }

            path.removeLast()
            stack.remove(serviceName)
            return nil
        }

        for serviceName in services.keys.sorted() {
            if let cycle = dfs(serviceName) {
                return cycle
            }
        }

        // Unreachable when Kahn stalls; return a stable placeholder if DFS finds no cycle.
        return services.keys.sorted()
    }
}
