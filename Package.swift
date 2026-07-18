// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VibeNotch",
    platforms: [.macOS(.v14)],
    targets: [
        // Shared: IPC protocol, event model, filesystem layout.
        .target(name: "VibeNotchCore"),

        // The menu-bar / notch app.
        .executableTarget(
            name: "VibeNotch",
            dependencies: ["VibeNotchCore"]
        ),

        // The hook client installed into agent configs.
        .executableTarget(
            name: "vibenotch-hook",
            dependencies: ["VibeNotchCore"]
        ),

        .testTarget(
            name: "VibeNotchCoreTests",
            dependencies: ["VibeNotchCore"]
        ),
    ]
)
