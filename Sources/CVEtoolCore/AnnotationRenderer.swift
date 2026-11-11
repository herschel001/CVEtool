import CoreGraphics
import CoreText
import Foundation

public struct AnnotationStroke: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case arrow, rect, ellipse, text, mosaic, highlight
    }

    public var kind: Kind
    public var start: CGPoint
    public var end: CGPoint
    public var text: String
    public var mosaicPoints: [CGPoint]
    public var red: Double
    public var green: Double
    public var blue: Double
    public var mosaicBlock: Double

    public init(
        kind: Kind,
        start: CGPoint,
        end: CGPoint,
        text: String = "",
        mosaicPoints: [CGPoint] = [],
        red: Double = 0,
        green: Double = 0.48,
        blue: Double = 1,
        mosaicBlock: Double = 16
    ) {
        self.kind = kind
        self.start = start
        self.end = end
        self.text = text
        self.mosaicPoints = mosaicPoints
        self.red = red
        self.green = green
        self.blue = blue
        self.mosaicBlock = mosaicBlock
    }

    public var cgColor: CGColor {
        CGColor(red: red, green: green, blue: blue, alpha: 1)
    }

    public var isVisible: Bool {
        switch kind {
        case .text:
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .mosaic:
            return mosaicPoints.count >= 1
        default:
            let dx = end.x - start.x
            let dy = end.y - start.y
            return (dx * dx + dy * dy) >= 16
        }
    }
}

public enum AnnotationRenderer {
    public static func render(base: CGImage, strokes: [AnnotationStroke], viewSize: CGSize) -> CGImage? {
        let width = base.width
        let height = base.height
        guard width > 0, height > 0, viewSize.width > 0, viewSize.height > 0 else { return nil }
        let scaleX = CGFloat(width) / viewSize.width
        let scaleY = CGFloat(height) / viewSize.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(base, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.saveGState()
        context.scaleBy(x: scaleX, y: scaleY)
        for stroke in strokes where stroke.isVisible {
            draw(stroke, in: context, pixelScale: scaleX)
        }
        context.restoreGState()
        applyMosaics(strokes, in: context, scaleX: scaleX, scaleY: scaleY)
        return context.makeImage()
    }

    private static func draw(_ stroke: AnnotationStroke, in context: CGContext, pixelScale: CGFloat) {
        switch stroke.kind {
        case .arrow:
            context.setStrokeColor(stroke.cgColor)
            context.setLineWidth(2.5 / pixelScale)
            context.setLineCap(.round)
            context.move(to: stroke.start)
            context.addLine(to: stroke.end)
            context.strokePath()
            let angle = atan2(stroke.end.y - stroke.start.y, stroke.end.x - stroke.start.x)
            let head: CGFloat = 12 / pixelScale
            let left = CGPoint(x: stroke.end.x - head * cos(angle - .pi / 6), y: stroke.end.y - head * sin(angle - .pi / 6))
            let right = CGPoint(x: stroke.end.x - head * cos(angle + .pi / 6), y: stroke.end.y - head * sin(angle + .pi / 6))
            context.move(to: left)
            context.addLine(to: stroke.end)
            context.addLine(to: right)
            context.strokePath()
        case .rect:
            context.setStrokeColor(stroke.cgColor)
            context.setLineWidth(2.5 / pixelScale)
            context.stroke(rect(from: stroke.start, to: stroke.end))
        case .ellipse:
            context.setStrokeColor(stroke.cgColor)
            context.setLineWidth(2.5 / pixelScale)
            context.strokeEllipse(in: rect(from: stroke.start, to: stroke.end))
        case .highlight:
            context.setFillColor(stroke.cgColor.copy(alpha: 0.45) ?? stroke.cgColor)
            context.fill(rect(from: stroke.start, to: stroke.end))
        case .text:
            let font = CTFontCreateWithName("PingFangSC-Regular" as CFString, 18 / pixelScale, nil)
            let color = stroke.cgColor
            let raw = CFAttributedStringCreateMutable(nil, 0)!
            CFAttributedStringReplaceString(raw, CFRange(location: 0, length: 0), stroke.text as CFString)
            let range = CFRange(location: 0, length: stroke.text.utf16.count)
            CFAttributedStringSetAttribute(raw, range, kCTFontAttributeName, font)
            CFAttributedStringSetAttribute(raw, range, kCTForegroundColorAttributeName, color)
            let line = CTLineCreateWithAttributedString(raw)
            context.textPosition = stroke.start
            CTLineDraw(line, context)
        case .mosaic:
            break
        }
    }

    private static func applyMosaics(_ strokes: [AnnotationStroke], in context: CGContext, scaleX: CGFloat, scaleY: CGFloat) {
        guard let image = context.makeImage() else { return }
        for stroke in strokes where stroke.kind == .mosaic && stroke.isVisible {
            let points = stroke.mosaicPoints.isEmpty ? [stroke.start, stroke.end] : stroke.mosaicPoints
            for point in points {
                let pixel = CGPoint(x: point.x * scaleX, y: point.y * scaleY)
                pixelate(context: context, image: image, center: pixel, radius: CGFloat(max(8, stroke.mosaicBlock)))
            }
        }
    }

    private static func pixelate(context: CGContext, image: CGImage, center: CGPoint, radius: CGFloat) {
        let block: CGFloat = 8
        let area = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            .integral
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard area.width >= block, area.height >= block else { return }
        var y = area.minY
        while y < area.maxY {
            var x = area.minX
            while x < area.maxX {
                let sample = CGRect(x: x, y: y, width: min(block, area.maxX - x), height: min(block, area.maxY - y))
                if let cropped = image.cropping(to: sample), let color = averageColor(cropped) {
                    context.setFillColor(color)
                    context.fill(sample)
                }
                x += block
            }
            y += block
        }
    }

    private static func averageColor(_ image: CGImage) -> CGColor? {
        guard let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: 4)
        return CGColor(red: CGFloat(pixels[0]) / 255, green: CGFloat(pixels[1]) / 255, blue: CGFloat(pixels[2]) / 255, alpha: 1)
    }

    private static func rect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }
}
