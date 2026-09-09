import AppKit

// Run from the repository root: swift docs/media/readme-hero-source/render.swift
// The screenshot is an actual app capture; its UI pixels are only scaled.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let width = 2880, height = 1600
let imageURL = root.appendingPathComponent("docs/media/readme-hero-source/recordings-window.png")
guard let screenshot = NSImage(contentsOf: imageURL) else { fatalError("Missing Recordings capture") }
func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1)
}
let ink = color(0xF5F8FF), secondary = color(0xBAC9E2), accent = color(0x79D0FF)
let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
    bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: 1, y: -1)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
context.setFillColor(color(0x101E38).cgColor)
context.fill(CGRect(x: 0, y: 0, width: width, height: height))
func text(_ value: String, x: CGFloat, y: CGFloat, width: CGFloat, size: CGFloat,
          weight: NSFont.Weight = .regular, color: NSColor = ink) {
    let style = NSMutableParagraphStyle(); style.lineSpacing = 10
    (value as NSString).draw(in: CGRect(x: x, y: y, width: width, height: 800), withAttributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color, .paragraphStyle: style
    ])
}
text("ScreenContext", x: 112, y: 105, width: 1100, size: 68, weight: .bold)
text("SCREEN RECORDINGS AS CONTEXT", x: 118, y: 385, width: 1120, size: 27, weight: .semibold, color: accent)
text("Use your screen\nrecording in your\nAI agent.", x: 108, y: 460, width: 1160, size: 105, weight: .bold)
text("Make a product video.\nFix a bug. Create a ticket.", x: 118, y: 935, width: 1100, size: 46, color: secondary)
text("Your everyday screen recorder, too.", x: 118, y: 1300, width: 1130, size: 34, color: ink)
text("Free for Mac  ·  Local MP4 recordings", x: 118, y: 1370, width: 1130, size: 28, color: accent)
let box = CGRect(x: 1300, y: 80, width: 1480, height: 1440)
let scale = min(box.width / screenshot.size.width, box.height / screenshot.size.height)
let rect = CGRect(x: box.midX - screenshot.size.width * scale / 2,
                  y: box.midY - screenshot.size.height * scale / 2,
                  width: screenshot.size.width * scale, height: screenshot.size.height * scale)
screenshot.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
NSGraphicsContext.restoreGraphicsState()
let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
let output = root.appendingPathComponent("docs/media/screencontext-readme-hero.png")
try bitmap.representation(using: .png, properties: [:])!.write(to: output)
print("Rendered \(width) × \(height) README hero.")
