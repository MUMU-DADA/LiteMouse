// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LiteMouse",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "LiteMouse", targets: ["LiteMouse"]),
    ],
    targets: [
        .target(name: "LiteMouseCore"),
        .executableTarget(
            name: "LiteMouse",
            dependencies: ["LiteMouseCore"]
        ),
        .testTarget(
            name: "LiteMouseCoreTests",
            dependencies: ["LiteMouseCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
