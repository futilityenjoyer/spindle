// swift-tools-version: 6.0
// Platform-independent logic (Foundation only). Builds and tests on Windows,
// Linux and macOS, so the riskiest logic gets a fast local feedback loop.
import PackageDescription

let package = Package(
    name: "Core",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Core", targets: ["Core"]),
    ],
    targets: [
        .target(name: "Core"),
        .testTarget(name: "CoreTests", dependencies: ["Core"]),
    ]
)
