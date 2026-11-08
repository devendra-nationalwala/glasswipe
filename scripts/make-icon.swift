// Renders Glasswipe's app icon to an .iconset folder. Usage: swift scripts/make-icon.swift <output.iconset>
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset")
try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func render(_ size: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = size * 0.1
    let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let shape = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)

    NSShadow().then { $0.shadowBlurRadius = size * 0.03; $0.shadowOffset = NSSize(width: 0, height: -size * 0.01)
        $0.shadowColor = NSColor.black.withAlphaComponent(0.3); $0.set() }
    NSGradient(colors: [NSColor(red: 0.20, green: 0.78, blue: 0.86, alpha: 1),
                        NSColor(red: 0.27, green: 0.36, blue: 0.95, alpha: 1),
                        NSColor(red: 0.47, green: 0.25, blue: 0.86, alpha: 1)])!.draw(in: shape, angle: -60)
    NSShadow().set()

    // Glass highlight across the top half.
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    let gloss = NSBezierPath(ovalIn: NSRect(x: rect.minX - rect.width * 0.3, y: rect.midY - rect.height * 0.05,
                                            width: rect.width * 1.6, height: rect.height * 1.1))
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.38), NSColor.white.withAlphaComponent(0.02)])!.draw(in: gloss, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    NSColor.white.withAlphaComponent(0.5).setStroke()
    shape.lineWidth = max(1, size * 0.006)
    shape.stroke()

    let config = NSImage.SymbolConfiguration(pointSize: size * 0.42, weight: .semibold)
        .applying(.init(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let s = symbol.size
        symbol.draw(in: NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2, width: s.width, height: s.height))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

extension NSShadow { func then(_ f: (NSShadow) -> Void) { f(self) } }

for base in [16, 32, 128, 256, 512] {
    try render(CGFloat(base)).write(to: output.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(CGFloat(base * 2)).write(to: output.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
