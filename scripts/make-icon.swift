#!/usr/bin/env swift
// Rebuild with: swift -module-cache-path /tmp/photo-viewer-icon-cache scripts/make-icon.swift
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let resources = root.appendingPathComponent("Resources")
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}

func rounded(_ rect: NSRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func render(size: Int) throws -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)

    // A dark, rounded macOS tile; the transparent margin leaves room for Dock shadows.
    let tile = rounded(NSRect(x: 66, y: 66, width: 892, height: 892), 200)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0.01, 0.02, 0.04, 0.30)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    color(0.10, 0.14, 0.20).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: color(0.18, 0.23, 0.32), ending: color(0.075, 0.10, 0.16))!
        .draw(in: tile, angle: -90)
    color(0.46, 0.58, 0.72, 0.26).setStroke()
    tile.lineWidth = 3
    tile.stroke()

    // The second card remains legible at small sizes without introducing fine details.
    NSGraphicsContext.saveGraphicsState()
    let transform = AffineTransform(translationByX: 510, byY: 530)
    var tilt = transform
    tilt.rotate(byDegrees: 10)
    tilt.translate(x: -510, y: -530)
    (tilt as NSAffineTransform).concat()
    let rear = rounded(NSRect(x: 198, y: 300, width: 632, height: 486), 60)
    color(0.20, 0.55, 0.79).setFill()
    rear.fill()
    NSGraphicsContext.restoreGraphicsState()

    let frame = rounded(NSRect(x: 184, y: 240, width: 656, height: 488), 56)
    NSGraphicsContext.saveGraphicsState()
    let cardShadow = NSShadow()
    cardShadow.shadowColor = color(0, 0, 0, 0.35)
    cardShadow.shadowBlurRadius = 30
    cardShadow.shadowOffset = NSSize(width: 0, height: -12)
    cardShadow.set()
    color(0.88, 0.95, 1).setFill()
    frame.fill()
    NSGraphicsContext.restoreGraphicsState()

    let picture = rounded(NSRect(x: 212, y: 268, width: 600, height: 432), 32)
    NSGraphicsContext.saveGraphicsState()
    picture.addClip()
    NSGradient(starting: color(0.14, 0.32, 0.53), ending: color(0.23, 0.62, 0.80))!
        .draw(in: picture, angle: 90)
    color(0.96, 0.82, 0.42).setFill()
    NSBezierPath(ovalIn: NSRect(x: 636, y: 536, width: 92, height: 92)).fill()
    let backMountain = NSBezierPath()
    backMountain.move(to: NSPoint(x: 410, y: 268))
    backMountain.line(to: NSPoint(x: 650, y: 520))
    backMountain.line(to: NSPoint(x: 880, y: 268))
    backMountain.close()
    color(0.21, 0.69, 0.70).setFill()
    backMountain.fill()
    let frontMountain = NSBezierPath()
    frontMountain.move(to: NSPoint(x: 150, y: 268))
    frontMountain.line(to: NSPoint(x: 415, y: 580))
    frontMountain.line(to: NSPoint(x: 705, y: 268))
    frontMountain.close()
    NSGradient(starting: color(0.40, 0.87, 0.75), ending: color(0.13, 0.57, 0.56))!
        .draw(in: frontMountain, angle: -90)
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        let file = iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png")
        try render(size: points * scale).write(to: file)
    }
}
try render(size: 512).write(to: resources.appendingPathComponent("AppIcon-preview.png"))
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    fputs("iconutil failed. In a restricted execution environment, retry iconutil with access to macOS image services.\n", stderr)
    exit(process.terminationStatus)
}
print("Generated Resources/AppIcon.icns and AppIcon-preview.png")
