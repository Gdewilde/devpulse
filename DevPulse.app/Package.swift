// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MemoryHealth",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MemoryHealth",
            path: "Sources"
        )
    ]
)
