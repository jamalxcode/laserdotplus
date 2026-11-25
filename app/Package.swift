// swift-tools-version:5.9
// Laserdot+: a window app for reviewing a large collection of files. It talks
// to the Go engine (laserdotd) over its Unix socket; nothing from the engine
// is linked. app/scripts/build-go.sh builds laserdotd (bundled beside the
// app) and regenerates Sources/LaserdotKit/Registry.generated.swift.
import PackageDescription

let package = Package(
    name: "LaserdotPlus",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "LaserdotPlus", targets: ["LaserdotPlus"]),
        .library(name: "LaserdotKit", targets: ["LaserdotKit"]),
    ],
    targets: [
        // The engine client and the registry-driven guidance — no UI.
        .target(name: "LaserdotKit", path: "Sources/LaserdotKit"),
        // The SwiftUI window app.
        .executableTarget(
            name: "LaserdotPlus",
            dependencies: ["LaserdotKit"],
            path: "Sources/LaserdotPlus",
            resources: [.process("Resources")]
        ),
        .testTarget(name: "LaserdotKitTests", dependencies: ["LaserdotKit"], path: "Tests/LaserdotKitTests"),
    ]
)
