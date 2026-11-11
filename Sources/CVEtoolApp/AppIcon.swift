import AppKit

enum AppIcon {
    static func statusImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { bounds in
            drawMark(in: bounds, viewBox: NSRect(x: 8, y: 8, width: 84, height: 84), color: .black)
            return true
        }
        image.isTemplate = true
        return image
    }

    static func applicationImage(size: CGFloat = 1024) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: true) { bounds in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            defer { context.restoreGState() }
            context.scaleBy(x: bounds.width / 100, y: bounds.height / 100)

            let tile = NSBezierPath()
            tile.move(to: NSPoint(x: 28, y: 4))
            tile.line(to: NSPoint(x: 72, y: 4))
            tile.curve(to: NSPoint(x: 96, y: 28), controlPoint1: NSPoint(x: 89, y: 4), controlPoint2: NSPoint(x: 96, y: 11))
            tile.line(to: NSPoint(x: 96, y: 72))
            tile.curve(to: NSPoint(x: 72, y: 96), controlPoint1: NSPoint(x: 96, y: 89), controlPoint2: NSPoint(x: 89, y: 96))
            tile.line(to: NSPoint(x: 28, y: 96))
            tile.curve(to: NSPoint(x: 4, y: 72), controlPoint1: NSPoint(x: 11, y: 96), controlPoint2: NSPoint(x: 4, y: 89))
            tile.line(to: NSPoint(x: 4, y: 28))
            tile.curve(to: NSPoint(x: 28, y: 4), controlPoint1: NSPoint(x: 4, y: 11), controlPoint2: NSPoint(x: 11, y: 4))
            tile.close()
            context.saveGState()
            tile.addClip()
            let gradient = NSGradient(
                starting: NSColor(srgbRed: 50 / 255, green: 205 / 255, blue: 164 / 255, alpha: 1),
                ending: NSColor(srgbRed: 8 / 255, green: 126 / 255, blue: 102 / 255, alpha: 1)
            )
            gradient?.draw(from: NSPoint(x: 4, y: 4), to: NSPoint(x: 36.2, y: 96), options: [.drawsBeforeStartingLocation, .drawsAfterEndingLocation])
            context.restoreGState()

            NSColor.white.withAlphaComponent(0.24).setStroke()
            let highlight = NSBezierPath()
            highlight.move(to: NSPoint(x: 28, y: 5))
            highlight.line(to: NSPoint(x: 72, y: 5))
            highlight.curve(to: NSPoint(x: 95, y: 28), controlPoint1: NSPoint(x: 88, y: 5), controlPoint2: NSPoint(x: 95, y: 12))
            highlight.lineWidth = 1
            highlight.stroke()
            drawMark(in: NSRect(x: 5, y: 5, width: 90, height: 90), viewBox: NSRect(x: 0, y: 0, width: 100, height: 100), color: .white)
            return true
        }
    }

    private static func drawMark(in bounds: NSRect, viewBox: NSRect, color: NSColor) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: bounds.minX, y: bounds.minY)
        context.scaleBy(x: bounds.width / viewBox.width, y: bounds.height / viewBox.height)
        context.translateBy(x: -viewBox.minX, y: -viewBox.minY)
        color.setStroke()
        let mark = NSBezierPath()
        mark.move(to: NSPoint(x: 82, y: 47))
        mark.line(to: NSPoint(x: 49, y: 80))
        mark.curve(to: NSPoint(x: 18, y: 68), controlPoint1: NSPoint(x: 37, y: 92), controlPoint2: NSPoint(x: 18, y: 84))
        mark.curve(to: NSPoint(x: 25, y: 51), controlPoint1: NSPoint(x: 18, y: 62), controlPoint2: NSPoint(x: 20, y: 56))
        mark.line(to: NSPoint(x: 61, y: 15))
        mark.curve(to: NSPoint(x: 81, y: 23), controlPoint1: NSPoint(x: 68, y: 8), controlPoint2: NSPoint(x: 81, y: 13))
        mark.curve(to: NSPoint(x: 76, y: 34), controlPoint1: NSPoint(x: 81, y: 27), controlPoint2: NSPoint(x: 79, y: 31))
        mark.line(to: NSPoint(x: 42, y: 68))
        mark.curve(to: NSPoint(x: 31, y: 64), controlPoint1: NSPoint(x: 38, y: 72), controlPoint2: NSPoint(x: 31, y: 69))
        mark.curve(to: NSPoint(x: 34, y: 58), controlPoint1: NSPoint(x: 31, y: 62), controlPoint2: NSPoint(x: 32, y: 60))
        mark.line(to: NSPoint(x: 63, y: 29))
        mark.lineWidth = 7
        mark.lineCapStyle = .round
        mark.lineJoinStyle = .round
        mark.stroke()
    }
}
