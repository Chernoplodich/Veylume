import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let output = root.appendingPathComponent("Configuration/Artwork")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
func png(_ size: NSSize, draw: () -> Void, at url: URL) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: Int(size.width) * 4, bitsPerPixel: 32)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    draw(); NSGraphicsContext.restoreGraphicsState()
    if url.lastPathComponent == "DMG-background.png" { bitmap.size = NSSize(width: size.width / 2, height: size.height / 2) }
    try bitmap.representation(using: .png, properties: [:])!.write(to: url)
}
// The approved brand is canonical. Never regenerate the former placeholder.
let kit = root.appendingPathComponent("Branding/Veylume-v1")
for (source, destination) in [
    (kit.appendingPathComponent("AppIcon.icns"), root.appendingPathComponent("Configuration/AppIcon.icns")),
    (kit.appendingPathComponent("AppIcon-1024.png"), output.appendingPathComponent("AppIcon-1024.png"))
] {
    let data = try Data(contentsOf: source)
    try data.write(to: destination, options: .atomic)
}
try png(NSSize(width: 1200, height: 840), draw: {
    let scale = NSAffineTransform(); scale.scale(by: 2); scale.concat()
    NSColor(calibratedRed: 0.93, green: 0.97, blue: 0.99, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: 600, height: 420).fill()
    let primary = NSColor(calibratedRed: 0.14, green: 0.23, blue: 0.32, alpha: 1)
    let secondary = NSColor(calibratedRed: 0.34, green: 0.44, blue: 0.54, alpha: 1)
    func text(_ string: String, top: CGFloat, height: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
        let style = NSMutableParagraphStyle(); style.alignment = .center
        (string as NSString).draw(in: NSRect(x: 24, y: 420 - top - height, width: 552, height: height), withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: style])
    }
    text("Veylume", top: 28, height: 34, size: 24, weight: .semibold, color: primary)
    if let arrow = NSImage(systemSymbolName: "arrow.right", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 28, weight: .medium)) {
        let tinted = NSImage(size: arrow.size, flipped: false) { rect in
            arrow.draw(in: rect); secondary.setFill(); rect.fill(using: .sourceAtop); return true
        }
        tinted.draw(in: NSRect(x: 284, y: 259, width: 32, height: 32))
    }
    text("Drag to Applications · Перетащите в Applications", top: 222, height: 24, size: 14, weight: .medium, color: primary)
    text("Arrastra a Aplicaciones · Glissez dans Applications", top: 252, height: 22, size: 14, weight: .regular, color: secondary)
}, at: output.appendingPathComponent("DMG-background.png"))
