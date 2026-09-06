// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Flare",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Flare", path: "Sources/Flare")
    ]
)
