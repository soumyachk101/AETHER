// swift-tools-version: 5.9
import Foundation
import PackageDescription

let packageDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let webView2SDK = ProcessInfo.processInfo.environment["WEBVIEW2_SDK_DIR"]
    ?? URL(fileURLWithPath: packageDirectory)
        .appendingPathComponent(".build/dependencies/Microsoft.Web.WebView2")
        .path
let webView2Include = "\(webView2SDK)/build/native/include"
let webView2Lib = "\(webView2SDK)/build/native/x64"

let package = Package(
    name: "AETHER",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/OpenCombine/OpenCombine.git", from: "0.14.0")
    ],
    products: [
        .executable(name: "AETHER", targets: ["AETHER"])
    ],
    targets: [
        .executableTarget(
            name: "AETHER",
            path: "Sources/AETHER",
            dependencies: [
                .product(name: "OpenCombine", package: "OpenCombine", condition: .when(platforms: [.linux, .windows])),
                .target(name: "CWebView2", condition: .when(platforms: [.windows]))
            ],
            linkerSettings: [
                .linkedLibrary("gtk-3", .when(platforms: [.linux])),
                .linkedLibrary("webkit2gtk-4.1", .when(platforms: [.linux]))
            ]
        ),
        .target(
            name: "CWebView2",
            path: "Sources/CWebView2",
            cxxSettings: [
                .unsafeFlags(["-I", webView2Include], .when(platforms: [.windows]))
            ],
            linkerSettings: [
                .unsafeFlags(["-L\(webView2Lib)", "-lWebView2LoaderStatic"], .when(platforms: [.windows])),
                .linkedLibrary("ole32", .when(platforms: [.windows])),
                .linkedLibrary("oleaut32", .when(platforms: [.windows])),
                .linkedLibrary("shell32", .when(platforms: [.windows])),
                .linkedLibrary("user32", .when(platforms: [.windows]))
            ]
        )
    ],
    swiftLanguageVersions: [.v5],
    cxxLanguageStandard: .cxx17
)
