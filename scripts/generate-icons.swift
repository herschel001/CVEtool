import AppKit
import Foundation

@main
enum IconGenerator {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw NSError(domain: "CVEtool.IconGenerator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Usage: generate-icons <output.iconset>"])
        }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let pixels = points * scale
                guard let bitmap = NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                    isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
                ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
                    throw NSError(domain: "CVEtool.IconGenerator", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not allocate icon bitmap"])
                }
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = context
                AppIcon.applicationImage(size: CGFloat(pixels)).draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
                NSGraphicsContext.restoreGraphicsState()
                guard let data = bitmap.representation(using: .png, properties: [:]) else {
                    throw NSError(domain: "CVEtool.IconGenerator", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not encode icon PNG"])
                }
                let suffix = scale == 2 ? "@2x" : ""
                try data.write(to: directory.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"), options: .atomic)
            }
        }
        print("Generated \(directory.path)")
    }
}
