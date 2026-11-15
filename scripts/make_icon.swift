// Draws the 轻舟助手 app icon (a white sailboat on a blue-teal rounded square) and writes
// Resources/AppIcon.icns. Run: swift scripts/make_icon.swift
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func draw(size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS icon grid: the rounded square fills ~80% of the canvas.
    let inset = s * 0.1
    let tile = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let shape = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.01)
    shadow.shadowBlurRadius = s * 0.02
    shadow.set()
    NSGradient(colors: [NSColor(red: 0.10, green: 0.46, blue: 0.96, alpha: 1),
                        NSColor(red: 0.07, green: 0.76, blue: 0.72, alpha: 1)])!.draw(in: shape, angle: -60)
    NSGraphicsContext.current?.restoreGraphicsState()

    // Water line.
    NSColor.white.withAlphaComponent(0.25).setFill()
    let wave = NSBezierPath()
    wave.move(to: NSPoint(x: tile.minX, y: tile.minY + tile.height * 0.26))
    wave.curve(to: NSPoint(x: tile.maxX, y: tile.minY + tile.height * 0.26),
               controlPoint1: NSPoint(x: tile.minX + tile.width * 0.33, y: tile.minY + tile.height * 0.34),
               controlPoint2: NSPoint(x: tile.minX + tile.width * 0.66, y: tile.minY + tile.height * 0.18))
    wave.line(to: NSPoint(x: tile.maxX, y: tile.minY))
    wave.line(to: NSPoint(x: tile.minX, y: tile.minY))
    wave.close()
    NSGraphicsContext.current?.saveGraphicsState()
    shape.addClip()
    wave.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    // Sailboat symbol in white.
    let config = NSImage.SymbolConfiguration(pointSize: s * 0.42, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let boat = NSImage(systemSymbolName: "sailboat.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        // Fit the boat into the middle of the tile, leaving a margin above the mast.
        let b = boat.size
        let k = min(tile.width * 0.56 / b.width, tile.height * 0.56 / b.height)
        let w = b.width * k, h = b.height * k
        boat.draw(in: NSRect(x: tile.midX - w / 2, y: tile.minY + tile.height * 0.2, width: w, height: h))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try draw(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try draw(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let out = root.appendingPathComponent("Resources/AppIcon.icns")
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try p.run()
p.waitUntilExit()
try draw(size: 512).write(to: root.appendingPathComponent("Resources/AppIcon-preview.png"))
print(p.terminationStatus == 0 ? "Wrote \(out.path)" : "iconutil failed")
