import Foundation

public struct ShutdownContainerPlan: Sendable, Equatable {
    public let layers: [[DiscoveredContainer]]
    public let orphans: [DiscoveredContainer]

    public init(layers: [[DiscoveredContainer]], orphans: [DiscoveredContainer]) {
        self.layers = layers
        self.orphans = orphans
    }
}
