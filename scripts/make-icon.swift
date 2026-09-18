import AppKit
import Foundation

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let factor = CGFloat(pixels) / 1024
        let transform = NSAffineTransform()
        transform.scale(by: factor)
        transform.concat()
        NSColor(calibratedRed: 0.09, green: 0.17, blue: 0.14, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 62, y: 62, width: 900, height: 900), xRadius: 205, yRadius: 205).fill()
        NSColor(calibratedRed: 0.46, green: 0.71, blue: 0.56, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 210, y: 365, width: 435, height: 420), xRadius: 70, yRadius: 70).fill()
        NSColor(calibratedRed: 0.77, green: 0.95, blue: 0.81, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 365, y: 230, width: 435, height: 420), xRadius: 70, yRadius: 70).fill()
        NSColor(calibratedRed: 0.09, green: 0.17, blue: 0.14, alpha: 1).setStroke()
        let line = NSBezierPath()
        line.lineWidth = 31
        line.lineCapStyle = .round
        line.move(to: NSPoint(x: 472, y: 502)); line.line(to: NSPoint(x: 535, y: 442)); line.line(to: NSPoint(x: 472, y: 382))
        line.move(to: NSPoint(x: 590, y: 382)); line.line(to: NSPoint(x: 678, y: 382)); line.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}
