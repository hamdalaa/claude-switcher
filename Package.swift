// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeSwitcher",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "ClaudeSwitcherCore", path: "Sources/ClaudeSwitcherCore"),
        .executableTarget(
            name: "ClaudeSwitcher",
            dependencies: ["ClaudeSwitcherCore"],
            path: "Sources/ClaudeSwitcher"
        ),
        .testTarget(
            name: "ClaudeSwitcherCoreTests",
            dependencies: ["ClaudeSwitcherCore"],
            path: "Tests/ClaudeSwitcherCoreTests"
        ),
    ]
)
