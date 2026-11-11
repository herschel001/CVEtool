import AppKit
import XCTest
@testable import CVEtoolApp

@MainActor
final class AppIconTests: XCTestCase {
    func testMenuIconIsAn18PointTemplateMatchingTheSelectedConcept() throws {
        let image = AppIcon.statusImage()
        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
        let actual = try rasterize(image, pixels: 36)
        let expected = try rasterize(approvedImage("04-paperclip-menu-light@2x.png"), pixels: 36)
        var alphaDifference: CGFloat = 0
        var visiblePixels = 0
        for y in 0..<36 {
            for x in 0..<36 {
                let alpha = try XCTUnwrap(actual.colorAt(x: x, y: y)).alphaComponent
                let expectedAlpha = try XCTUnwrap(expected.colorAt(x: x, y: y)).alphaComponent
                alphaDifference += abs(alpha - expectedAlpha)
                if alpha > 0.5 { visiblePixels += 1 }
            }
        }
        XCTAssertGreaterThan(visiblePixels, 150)
        XCTAssertLessThan(visiblePixels, 900)
        XCTAssertLessThan(alphaDifference / (36 * 36), 0.04)
    }

    func testApplicationIconHasTransparentCornersAndTheApprovedWhiteMark() throws {
        let actual = try rasterize(AppIcon.applicationImage(size: 128), pixels: 128)
        let expected = try rasterize(approvedImage("04-paperclip-app.png"), pixels: 128)
        XCTAssertEqual(try XCTUnwrap(actual.colorAt(x: 0, y: 0)).alphaComponent, 0)
        XCTAssertGreaterThan(try XCTUnwrap(actual.colorAt(x: 64, y: 64)).alphaComponent, 0.99)
        var differentPixels = 0
        var whitePixels = 0
        for y in 0..<128 {
            for x in 0..<128 {
                let rendered = try XCTUnwrap(actual.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                let reference = try XCTUnwrap(expected.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                let isWhite = rendered.alphaComponent > 0.8 && min(rendered.redComponent, rendered.greenComponent, rendered.blueComponent) > 0.9
                let wasWhite = reference.alphaComponent > 0.8 && min(reference.redComponent, reference.greenComponent, reference.blueComponent) > 0.9
                if isWhite { whitePixels += 1 }
                if isWhite != wasWhite { differentPixels += 1 }
            }
        }
        XCTAssertGreaterThan(whitePixels, 1000)
        XCTAssertLessThan(Double(differentPixels) / (128 * 128), 0.025)
    }

    private func approvedImage(_ filename: String) throws -> NSImage {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try XCTUnwrap(NSImage(contentsOf: root.appendingPathComponent("docs/icon-concepts/\(filename)")))
    }

    private func rasterize(_ image: NSImage, pixels: Int) throws -> NSBitmapImageRep {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        return bitmap
    }
}
