// Draws the Nextlet app icon (ink square, white chevron, yellow dot) into an
// .iconset folder for iconutil. Usage: swift scripts/make-icon.swift <out.iconset>
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset")
try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

func render(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let size = CGFloat(pixels)
    // Apple's icon grid: the artwork fills about 80% of the canvas.
    let inset = size * 0.1
    let tile = NSRect(x: inset, y: inset * 1.15, width: size - inset * 2, height: size - inset * 2)

    if pixels >= 64 {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        shadow.shadowBlurRadius = size * 0.025
        shadow.shadowOffset = NSSize(width: 0, height: -size * 0.012)
        shadow.set()
    }
    color(0x15171C).setFill()
    NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225).fill()
    NSShadow().set()

    let unit = tile.width / 24
    func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: tile.minX + x * unit, y: tile.maxY - y * unit) }
    let chevron = NSBezierPath()
    chevron.move(to: point(8, 6.5))
    chevron.line(to: point(13.5, 12))
    chevron.line(to: point(8, 17.5))
    chevron.lineWidth = 2.6 * unit
    chevron.lineCapStyle = .round
    chevron.lineJoinStyle = .round
    NSColor.white.setStroke()
    chevron.stroke()
    color(0xFFD84D).setFill()
    NSBezierPath(ovalIn: NSRect(x: tile.minX + 15.5 * unit, y: tile.maxY - 14 * unit, width: 4 * unit, height: 4 * unit)).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: output.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: output.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
print("Wrote \(output.path)")
