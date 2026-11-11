import CoreGraphics
import XCTest
@testable import CVEtoolCore

final class CapacityPolicyTests: XCTestCase {
    func testRejectsItemLargerThanLimit() {
        let old = CapacityItem(id: UUID(), createdAt: Date(timeIntervalSince1970: 1), byteSize: 30)
        let decision = CapacityPolicy.planInsert(items: [old], incomingBytes: 80, limitBytes: 50)
        XCTAssertEqual(decision, .rejectOversized)
    }

    func testDeletesOldestUntilTheNewItemFits() {
        let oldest = CapacityItem(id: UUID(), createdAt: Date(timeIntervalSince1970: 1), byteSize: 30)
        let newer = CapacityItem(id: UUID(), createdAt: Date(timeIntervalSince1970: 2), byteSize: 160)
        let decision = CapacityPolicy.planInsert(items: [newer, oldest], incomingBytes: 20, limitBytes: 200)
        XCTAssertEqual(decision, .insert(evicting: [oldest.id]))
    }

    func testShrinksImmediatelyWhenLimitDrops() {
        let oldest = CapacityItem(id: UUID(), createdAt: Date(timeIntervalSince1970: 1), byteSize: 90)
        let newer = CapacityItem(id: UUID(), createdAt: Date(timeIntervalSince1970: 2), byteSize: 90)
        let victims = CapacityPolicy.planShrink(items: [newer, oldest], limitBytes: 100)
        XCTAssertEqual(victims, [oldest.id])
    }
}

final class ClipboardClassifierTests: XCTestCase {
    func testPlainText() {
        XCTAssertEqual(ClipboardClassifier.classify(text: "明天下午三点，会议室 B", imagePNG: nil, fileOnly: false), .text("明天下午三点，会议室 B"))
    }

    func testLinkAndColorAreNotAlsoText() {
        XCTAssertEqual(ClipboardClassifier.classify(text: "https://developer.apple.com/documentation/appkit/nspasteboard", imagePNG: nil, fileOnly: false), .link("https://developer.apple.com/documentation/appkit/nspasteboard"))
        XCTAssertEqual(ClipboardClassifier.classify(text: "#3d7a5a", imagePNG: nil, fileOnly: false), .color("#3D7A5A"))
        XCTAssertEqual(ClipboardClassifier.normalizedColor("rgb(61, 122, 90)"), "#3D7A5A")
    }

    func testSentenceContainingALinkStaysText() {
        XCTAssertEqual(
            ClipboardClassifier.classify(text: "看这个 https://example.com", imagePNG: nil, fileOnly: false),
            .text("看这个 https://example.com")
        )
    }

    func testFileOnlyIsIgnored() {
        XCTAssertEqual(ClipboardClassifier.classify(text: nil, imagePNG: nil, fileOnly: true), .ignore)
        XCTAssertEqual(ClipboardClassifier.classify(text: "  ", imagePNG: nil, fileOnly: false), .ignore)
    }

    func testImageWinsOverText() {
        let data = Data([0x89, 0x50, 0x4E, 0x47])
        XCTAssertEqual(ClipboardClassifier.classify(text: "说明", imagePNG: data, fileOnly: false), .image(data))
    }
}

final class HistoryStoreTests: XCTestCase {
    func testDuplicateMovesToFrontAndSurvivesReload() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = HistoryStore(directory: dir)
        let limit = CapacityPolicy.bytes(fromMegabytes: 200)
        let first = store.addText(kind: .text, text: "明天下午三点，会议室 B", limitBytes: limit, now: Date(timeIntervalSince1970: 10))
        guard case .inserted = first else { return XCTFail("expected insert") }
        let again = store.addText(kind: .text, text: "明天下午三点，会议室 B", limitBytes: limit, now: Date(timeIntervalSince1970: 20))
        guard case .movedToFront = again else { return XCTFail("expected move") }
        XCTAssertEqual(store.snapshot().count, 1)

        let reloaded = HistoryStore(directory: dir)
        XCTAssertEqual(reloaded.snapshot().map(\.text), ["明天下午三点，会议室 B"])
        XCTAssertEqual(reloaded.snapshot().first?.createdAt, Date(timeIntervalSince1970: 20))
    }

    func testScreenshotAppearsInImageAndScreenshotFilters() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = HistoryStore(directory: dir)
        let limit = CapacityPolicy.bytes(fromMegabytes: 200)
        let png = Self.solidPNG(color: (220, 40, 40))
        _ = store.addImage(png, isScreenshot: true, limitBytes: limit)
        XCTAssertEqual(store.filtered(.screenshot, query: "").count, 1)
        XCTAssertEqual(store.filtered(.image, query: "").count, 1)
        XCTAssertEqual(store.filtered(.text, query: "").count, 0)
    }

    func testOversizedImageIsRejectedWithoutDeletingHistory() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = HistoryStore(directory: dir)
        let smallLimit: Int64 = 32
        _ = store.addText(kind: .text, text: "留下", limitBytes: smallLimit)
        let result = store.addImage(Data(repeating: 1, count: 80), isScreenshot: false, limitBytes: smallLimit)
        XCTAssertEqual(result, .rejectedOversized)
        XCTAssertEqual(store.snapshot().map(\.text), ["留下"])
    }

    func testSearchAndEmptyQuery() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = HistoryStore(directory: dir)
        let limit = CapacityPolicy.bytes(fromMegabytes: 50)
        _ = store.addText(kind: .text, text: "会议室 B", limitBytes: limit)
        _ = store.addText(kind: .link, text: "https://example.com", limitBytes: limit)
        XCTAssertEqual(store.filtered(.all, query: "会议室").count, 1)
        XCTAssertEqual(store.filtered(.all, query: "没有这个词").count, 0)
    }

    private static func solidPNG(color: (UInt8, UInt8, UInt8)) -> Data {
        let width = 4
        let height = 4
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            pixels[i * 4] = color.0
            pixels[i * 4 + 1] = color.1
            pixels[i * 4 + 2] = color.2
            pixels[i * 4 + 3] = 255
        }
        let space = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let image = context.makeImage()!
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        return data as Data
    }
}

final class GeometryAndAnnotationTests: XCTestCase {
    func testCaptureRectMatchesSelectedAreaAcrossDisplayLayouts() {
        let cases: [(String, CGRect, CGRect)] = [
            ("top of primary display", CGRect(x: 100, y: 700, width: 300, height: 200), CGRect(x: 100, y: 100, width: 300, height: 200)),
            ("bottom of primary display", CGRect(x: 100, y: 100, width: 300, height: 200), CGRect(x: 100, y: 700, width: 300, height: 200)),
            ("display to the left", CGRect(x: -1200, y: 300, width: 400, height: 200), CGRect(x: -1200, y: 500, width: 400, height: 200)),
            ("display to the right", CGRect(x: 1600, y: 200, width: 400, height: 300), CGRect(x: 1600, y: 500, width: 400, height: 300)),
            ("display above primary", CGRect(x: 100, y: 1200, width: 300, height: 200), CGRect(x: 100, y: -400, width: 300, height: 200)),
            ("display below primary", CGRect(x: 100, y: -600, width: 300, height: 200), CGRect(x: 100, y: 1400, width: 300, height: 200)),
            ("entire primary display", CGRect(x: 0, y: 0, width: 1600, height: 1000), CGRect(x: 0, y: 0, width: 1600, height: 1000)),
        ]
        for (layout, selection, expected) in cases {
            let captured = ScreenGeometry.captureRect(fromAppKitSelection: selection, primaryHeight: 1000)
            XCTAssertEqual(captured, expected, layout)
            XCTAssertEqual(ScreenGeometry.appKitRect(fromCGWindowBounds: captured, primaryHeight: 1000), selection, layout)
        }
    }

    func testWindowPickerSkipsDockAndOwnOverlay() {
        let dock = WindowCandidate(owner: "Dock", layer: 0, alpha: 1, bounds: CGRect(x: 0, y: 800, width: 1400, height: 80), ownerPID: 2)
        let overlay = WindowCandidate(owner: "CVEtool", layer: 0, alpha: 1, bounds: CGRect(x: 0, y: 0, width: 1400, height: 900), ownerPID: 99)
        let notes = WindowCandidate(owner: "Notes", layer: 0, alpha: 1, bounds: CGRect(x: 200, y: 120, width: 600, height: 400), ownerPID: 7)
        let hit = WindowPicker.hit(candidates: [dock, overlay, notes], cgPoint: CGPoint(x: 300, y: 200), ownPID: 99)
        XCTAssertEqual(hit, notes.bounds)
    }

    func testWindowBoundsFlip() {
        let converted = ScreenGeometry.appKitRect(
            fromCGWindowBounds: CGRect(x: 10, y: 20, width: 100, height: 40),
            primaryHeight: 1000
        )
        XCTAssertEqual(converted, CGRect(x: 10, y: 940, width: 100, height: 40))
    }

    func testToolbarMovesAboveSelectionWhenBottomDoesNotFit() {
        let screen = CGRect(x: 0, y: 0, width: 800, height: 600)
        let selection = CGRect(x: 100, y: 4, width: 200, height: 80)
        let frame = ScreenGeometry.toolbarFrame(selection: selection, toolbarSize: CGSize(width: 420, height: 40), screen: screen)
        XCTAssertGreaterThan(frame.minY, selection.maxY)
    }

    func testToolbarAlignsWithSelectionRightEdgeAndStaysOnScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1400, height: 900)
        let size = CGSize(width: 546, height: 48)
        let selection = CGRect(x: 700, y: 300, width: 400, height: 200)
        let frame = ScreenGeometry.toolbarFrame(selection: selection, toolbarSize: size, screen: screen)
        XCTAssertEqual(frame.maxX, selection.maxX)
        XCTAssertEqual(frame.maxY, selection.minY - 12)

        let leftSelection = CGRect(x: 10, y: 300, width: 100, height: 200)
        let clamped = ScreenGeometry.toolbarFrame(selection: leftSelection, toolbarSize: size, screen: screen)
        XCTAssertEqual(clamped.minX, screen.minX + 8)
        XCTAssertTrue(screen.contains(clamped))
    }

    func testFullscreenToolbarIsCenteredOnThatScreen() {
        let screen = CGRect(x: 1440, y: 0, width: 800, height: 600)
        let frame = ScreenGeometry.fullscreenToolbarFrame(toolbarSize: CGSize(width: 200, height: 36), screen: screen)
        XCTAssertEqual(frame.midX, screen.midX, accuracy: 0.1)
        XCTAssertGreaterThan(frame.minY, screen.minY)
    }

    func testMosaicChangesPixelsUnderTheStroke() throws {
        let base = try XCTUnwrap(Self.solidImage(width: 40, height: 40, color: (10, 180, 30), hotspot: (20, 20)))
        let stroke = AnnotationStroke(kind: .mosaic, start: CGPoint(x: 20, y: 20), end: CGPoint(x: 20, y: 20), mosaicPoints: [CGPoint(x: 20, y: 20)])
        let rendered = try XCTUnwrap(AnnotationRenderer.render(base: base, strokes: [stroke], viewSize: CGSize(width: 40, height: 40)))
        let before = try XCTUnwrap(Self.pixel(base, x: 20, y: 20))
        let after = try XCTUnwrap(Self.pixel(rendered, x: 20, y: 20))
        XCTAssertNotEqual(before.0, after.0)
    }

    private static func solidImage(width: Int, height: Int, color: (UInt8, UInt8, UInt8), hotspot: (Int, Int)? = nil) -> CGImage? {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            pixels[i * 4] = color.0
            pixels[i * 4 + 1] = color.1
            pixels[i * 4 + 2] = color.2
            pixels[i * 4 + 3] = 255
        }
        if let hotspot {
            let offset = (hotspot.1 * width + hotspot.0) * 4
            pixels[offset] = 255
            pixels[offset + 1] = 0
            pixels[offset + 2] = 0
        }
        let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        return context?.makeImage()
    }

    private static func pixel(_ image: CGImage, x: Int, y: Int) -> (UInt8, UInt8, UInt8)? {
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return nil }
        let offset = (y * image.bytesPerRow) + x * 4
        return (bytes[offset], bytes[offset + 1], bytes[offset + 2])
    }
}
