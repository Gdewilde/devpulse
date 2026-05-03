// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DevPulse",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DevPulse",
            path: "Sources"
        ),
        .testTarget(
            name: "DevPulseTests",
            dependencies: ["DevPulse"],
            path: "Tests"
        )
    ]
)
