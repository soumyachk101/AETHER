// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AETHER",
    // The desktop client uses AppKit and SwiftUI and is supported on macOS only.
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
