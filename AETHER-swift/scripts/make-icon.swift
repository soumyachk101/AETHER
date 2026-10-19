import AppKit
import Foundation

let output = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "AppIcon.iconset"
try? FileManager.default.createDirectory(
    atPath: output,
    withIntermediateDirectories: true
)

func starPath(center: NSPoint, radius: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    let waist = radius * 0.16
    path.move(to: NSPoint(x: center.x, y: center.y + radius))
    path.curve(
        to: NSPoint(x: center.x + radius, y: center.y),
        controlPoint1: NSPoint(x: center.x + waist, y: center.y + waist),
        controlPoint2: NSPoint(x: center.x + waist, y: center.y + waist)
    )
    path.curve(
        to: NSPoint(x: center.x, y: center.y - radius),
        controlPoint1: NSPoint(x: center.x + waist, y: center.y - waist),
        controlPoint2: NSPoint(x: center.x + waist, y: center.y - waist)
    )
    path.curve(
        to: NSPoint(x: center.x - radius, y: center.y),
        controlPoint1: NSPoint(x: center.x - waist, y: center.y - waist),
        controlPoint2: NSPoint(x: center.x - waist, y: center.y - waist)
    )
    path.curve(
        to: NSPoint(x: center.x, y: center.y + radius),
        controlPoint1: NSPoint(x: center.x - waist, y: center.y + waist),
        controlPoint2: NSPoint(x: center.x - waist, y: center.y + waist)
    )
    path.close()
    return path
}

func render(size: Int) -> Data? {
    let dim = CGFloat(size)
    let image = NSImage(size: NSSize(width: dim, height: dim))
    image.lockFocus()

    let inset = dim * 0.055
    let rect = NSRect(x: inset, y: inset, width: dim - inset * 2, height: dim - inset * 2)
    let radius = dim * 0.225
    let plate = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

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

    let center = NSPoint(x: dim / 2, y: dim / 2)
    NSColor.white.setFill()
    starPath(center: center, radius: dim * 0.235).fill()

    NSColor.white.withAlphaComponent(0.92).setFill()
    starPath(
        center: NSPoint(x: dim * 0.725, y: dim * 0.71),
        radius: dim * 0.072
    ).fill()

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
