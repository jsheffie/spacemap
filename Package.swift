// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "spacemap",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "SpacemapCore",
            path: "Sources/SpacemapCore"
        ),
        .executableTarget(
            name: "spacemap",
            dependencies: ["SpacemapCore"],
            path: "Sources/spacemap",
            exclude: ["Info.plist"]
        ),
        .executableTarget(
            name: "spacemap-ls",
            dependencies: ["SpacemapCore"],
            path: "Sources/spacemap-ls"
        )
    ]
)
