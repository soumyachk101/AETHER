// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AETHER",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "AETHER", targets: ["AETHER"])
    ],
    targets: [
        .executableTarget(
            name: "AETHER",
            path: "Sources/AETHER"
        )
    ]
)
