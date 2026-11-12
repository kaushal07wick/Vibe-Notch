// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VibeNotch",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Pinned MIT sources with Command Line Tools compatibility fixes.
        // See Vendor/DynamicNotchKit/UPSTREAM.md for provenance and changes.
        .package(path: "Vendor/DynamicNotchKit"),
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

        // Scriptable control: vibenotch list|approve|deny|send|interrupt
        .executableTarget(
            name: "VibeNotchCLI",
            dependencies: ["VibeNotchCore"]
        ),

        .testTarget(
            name: "VibeNotchCoreTests",
            dependencies: ["VibeNotchCore"]
        ),
    ]
)
