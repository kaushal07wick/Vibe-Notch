// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VibeNotch",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Notch window, hover-expand, and morph physics (MIT). Pinned to main —
        // the compact/hover API isn't in a tagged release yet.
        .package(url: "https://github.com/MrKai77/DynamicNotchKit",
                 revision: "cd0b3e52d537db115ad3a9d89601f20e0bee8d27"),
    ],
    targets: [
        // Shared: IPC protocol, event model, filesystem layout.
        .target(name: "VibeNotchCore"),

        // The menu-bar / notch app.
        .executableTarget(
            name: "VibeNotch",
            dependencies: [
                "VibeNotchCore",
                .product(name: "DynamicNotchKit", package: "DynamicNotchKit"),
            ]
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
