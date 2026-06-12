// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "compose",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/apple/container.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/containerization.git", exact: "0.33.3"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.1"),
    ],
    targets: [
        .target(
            name: "ComposeCore",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "ContainerAPIClient", package: "container"),
                .product(name: "ContainerCommands", package: "container"),
                .product(name: "MachineAPIClient", package: "container"),
                .product(name: "Containerization", package: "containerization"),
                .product(name: "ContainerizationArchive", package: "containerization"),
                .product(name: "ContainerizationOS", package: "containerization"),
                .product(name: "Yams", package: "Yams"),
            ],
            path: "Sources/ComposeCore"
        ),
        .executableTarget(
            name: "compose",
            dependencies: ["ComposeCore"],
            path: "Sources/compose"
        ),
        .executableTarget(
            name: "compose-verify",
            dependencies: [
                "ComposeCore",
                .product(name: "ContainerCommands", package: "container"),
                .product(name: "ContainerResource", package: "container"),
                .product(name: "Containerization", package: "containerization"),
                .product(name: "ContainerizationExtras", package: "containerization"),
            ],
            path: "Sources/compose-verify"
        ),
    ],
    swiftLanguageModes: [.v6]
)
