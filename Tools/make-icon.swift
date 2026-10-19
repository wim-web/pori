import AppKit
import Foundation

let destination = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let p = CGFloat(pixels)
        let transform = AffineTransform(scale: p / 1024)
        (transform as NSAffineTransform).concat()
        let rect = NSRect(x: 80, y: 80, width: 864, height: 864)
        let background = NSBezierPath(roundedRect: rect, xRadius: 205, yRadius: 205)
        NSGradient(starting: NSColor(srgbRed: 0.16, green: 0.52, blue: 0.46, alpha: 1), ending: NSColor(srgbRed: 0.06, green: 0.30, blue: 0.28, alpha: 1))!.draw(in: background, angle: 270)
        NSColor(srgbRed: 0.81, green: 0.97, blue: 0.90, alpha: 1).setStroke()
        let arrow = NSBezierPath()
        arrow.lineWidth = 64
        arrow.lineCapStyle = .round
        arrow.lineJoinStyle = .round
        arrow.move(to: NSPoint(x: 320, y: 330)); arrow.line(to: NSPoint(x: 700, y: 710))
        arrow.move(to: NSPoint(x: 436, y: 710)); arrow.line(to: NSPoint(x: 700, y: 710)); arrow.line(to: NSPoint(x: 700, y: 446))
        arrow.stroke()
        NSColor.white.withAlphaComponent(0.27).setStroke()
        let second = NSBezierPath()
        second.lineWidth = 40; second.lineCapStyle = .round
        second.move(to: NSPoint(x: 550, y: 315)); second.line(to: NSPoint(x: 705, y: 315)); second.line(to: NSPoint(x: 705, y: 340)); second.stroke()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let name = "icon_\(size)x\(size)" + (scale == 2 ? "@2x" : "") + ".png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(name))
    }
}
if CommandLine.arguments.count > 2 {
    func uint32(_ value: Int) -> Data {
        var number = UInt32(value).bigEndian
        return withUnsafeBytes(of: &number) { Data($0) }
    }
    var entries = Data()
    for (type, filename) in [("icp4", "icon_16x16.png"), ("icp5", "icon_32x32.png"), ("icp6", "icon_32x32@2x.png"), ("ic07", "icon_128x128.png"), ("ic08", "icon_256x256.png"), ("ic09", "icon_512x512.png"), ("ic10", "icon_512x512@2x.png")] {
        let bytes = try Data(contentsOf: destination.appendingPathComponent(filename))
        entries.append(Data(type.utf8)); entries.append(uint32(bytes.count + 8)); entries.append(bytes)
    }
    var archive = Data("icns".utf8)
    archive.append(uint32(entries.count + 8)); archive.append(entries)
    try archive.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
}
