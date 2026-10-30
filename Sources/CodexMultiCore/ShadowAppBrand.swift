import AppKit

/// Shared artwork for the app bundle, sidebar, and menu bar.
public enum ShadowAppBrand {
    public static let name = "ShadowApp"

    public static func image(size: CGFloat, template: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            let transform = NSAffineTransform()
            transform.scale(by: size / 1024)
            transform.concat()

            if !template {
                let tile = NSBezierPath(roundedRect: NSRect(x: 62, y: 62, width: 900, height: 900),
                                        xRadius: 205, yRadius: 205)
                NSGradient(starting: NSColor(calibratedWhite: 0.20, alpha: 1),
                           ending: NSColor(calibratedWhite: 0.085, alpha: 1))!.draw(in: tile, angle: -70)
            }

            // The offset echo belongs to the mark, rather than a platform shadow.
            let echo = mark()
            let offset = AffineTransform(translationByX: 48, byY: -42)
            echo.transform(using: offset)
            (template ? NSColor.black.withAlphaComponent(0.35)
                      : NSColor(calibratedRed: 0.55, green: 0.49, blue: 0.95, alpha: 1)).setStroke()
            echo.stroke()
            (template ? NSColor.black : NSColor(calibratedWhite: 0.97, alpha: 1)).setStroke()
            mark().stroke()
            return true
        }
        image.isTemplate = template
        return image
    }

    private static func mark() -> NSBezierPath {
        let path = NSBezierPath()
        path.lineWidth = 112
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: NSPoint(x: 672, y: 730))
        path.line(to: NSPoint(x: 438, y: 730))
        path.curve(to: NSPoint(x: 318, y: 610), controlPoint1: NSPoint(x: 364, y: 730), controlPoint2: NSPoint(x: 318, y: 684))
        path.curve(to: NSPoint(x: 438, y: 490), controlPoint1: NSPoint(x: 318, y: 536), controlPoint2: NSPoint(x: 364, y: 490))
        path.line(to: NSPoint(x: 546, y: 490))
        path.curve(to: NSPoint(x: 666, y: 370), controlPoint1: NSPoint(x: 620, y: 490), controlPoint2: NSPoint(x: 666, y: 444))
        path.curve(to: NSPoint(x: 546, y: 250), controlPoint1: NSPoint(x: 666, y: 296), controlPoint2: NSPoint(x: 620, y: 250))
        path.line(to: NSPoint(x: 312, y: 250))
        return path
    }
}
