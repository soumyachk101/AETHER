import AppKit
import Foundation

let output = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "AppIcon.iconset"
try? FileManager.default.createDirectory(
    atPath: output,
    withIntermediateDirectories: true
)

let scriptDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let swiftDir = scriptDir.deletingLastPathComponent()
let repoDir = swiftDir.deletingLastPathComponent()

let sourceCandidates = [
    repoDir.appendingPathComponent("image.png"),
    swiftDir.appendingPathComponent("Sources/AETHER/Resources/logo.png"),
    repoDir.appendingPathComponent("AETHER-web/public/logo.png")
]

var baseSourceImage: NSImage?
for url in sourceCandidates {
    if FileManager.default.fileExists(atPath: url.path),
       let img = NSImage(contentsOf: url) {
        baseSourceImage = img
        break
    }
}

func render(size: Int) -> Data? {
    let dim = CGFloat(size)
    let image = NSImage(size: NSSize(width: dim, height: dim))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: dim, height: dim)

    if let source = baseSourceImage {
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
    } else {
        let inset = dim * 0.055
        let plateRect = NSRect(x: inset, y: inset, width: dim - inset * 2, height: dim - inset * 2)
        let radius = dim * 0.225
        let plate = NSBezierPath(roundedRect: plateRect, xRadius: radius, yRadius: radius)
        let gradient = NSGradient(
            colors: [
                NSColor(srgbRed: 0.45, green: 0.36, blue: 1.0, alpha: 1),
                NSColor(srgbRed: 0.24, green: 0.78, blue: 0.94, alpha: 1)
            ]
        )
        gradient?.draw(in: plate, angle: -55)
        NSColor.white.withAlphaComponent(0.18).setStroke()
        plate.lineWidth = max(1, dim * 0.012)
        plate.stroke()
    }

    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff)
    else { return nil }
    return rep.representation(using: .png, properties: [:])
}

let names: [Int: [String]] = [
    16: ["icon_16x16.png"],
    32: ["icon_16x16@2x.png", "icon_32x32.png"],
    64: ["icon_32x32@2x.png"],
    128: ["icon_128x128.png"],
    256: ["icon_128x128@2x.png", "icon_256x256.png"],
    512: ["icon_256x256@2x.png", "icon_512x512.png"],
    1024: ["icon_512x512@2x.png"]
]

for (size, fileNames) in names {
    guard let data = render(size: size) else { continue }
    for name in fileNames {
        try? data.write(to: URL(fileURLWithPath: output).appendingPathComponent(name))
    }
}
