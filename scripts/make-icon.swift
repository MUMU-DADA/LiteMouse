import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: swift make-icon.swift <output.iconset>\n", stderr)
    exit(1)
}

let iconsetURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

func renderIcon(size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: s, height: s)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Rounded macOS squircle background
    let inset = s * 0.08
    let bgRect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: s * 0.22, yRadius: s * 0.22)
    let gradient = NSGradient(
        starting: NSColor(calibratedRed: 0.14, green: 0.19, blue: 0.28, alpha: 1.0),
        ending: NSColor(calibratedRed: 0.08, green: 0.11, blue: 0.17, alpha: 1.0)
    )!
    gradient.draw(in: bgPath, angle: -90)

    // Subtle border
    NSColor(calibratedWhite: 1.0, alpha: 0.14).setStroke()
    bgPath.lineWidth = max(1.0, s * 0.014)
    bgPath.stroke()

    // Minimalist mouse silhouette
    let mw = s * 0.40
    let mh = s * 0.56
    let mRect = NSRect(x: (s - mw) / 2, y: (s - mh) / 2, width: mw, height: mh)
    let mousePath = NSBezierPath(roundedRect: mRect, xRadius: mw * 0.48, yRadius: mw * 0.48)
    NSColor(calibratedWhite: 0.96, alpha: 0.95).setFill()
    mousePath.fill()

    // Scroll wheel accent
    let ww = mw * 0.17
    let wh = mh * 0.22
    let wRect = NSRect(x: (s - ww) / 2, y: mRect.maxY - mh * 0.34, width: ww, height: wh)
    let wheelPath = NSBezierPath(roundedRect: wRect, xRadius: ww * 0.5, yRadius: ww * 0.5)
    NSColor(calibratedRed: 0.16, green: 0.58, blue: 0.98, alpha: 1.0).setFill()
    wheelPath.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let specs: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for (name, px) in specs {
    try renderIcon(size: px).write(to: iconsetURL.appendingPathComponent(name))
}
