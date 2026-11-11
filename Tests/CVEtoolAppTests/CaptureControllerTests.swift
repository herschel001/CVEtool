import AppKit
import XCTest
@testable import CVEtoolApp

@MainActor
final class CaptureControllerTests: XCTestCase {
    func testMovingScreenshotKeepsCapturedImageWithoutRequestingAnotherCapture() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1000, height: 800), styleMask: .borderless, backing: .buffered, defer: false)
        let controller = CaptureController()
        defer { controller.cancel() }
        let image = try makeImage()
        let original = CGRect(x: 100, y: 100, width: 400, height: 300)
        controller.beginEditing(image, selection: original, in: window)
        let start = window.convertPoint(fromScreen: CGPoint(x: 250, y: 250))
        let end = window.convertPoint(fromScreen: CGPoint(x: 330, y: 310))

        controller.mouseDown(at: start)
        controller.mouseDragged(to: end)
        controller.mouseUp(at: end)

        XCTAssertEqual(controller.selection, original.offsetBy(dx: 80, dy: 60))
        XCTAssertTrue(controller.image === image)
        XCTAssertNil(controller.captureRequestID, "Moving a captured image must never re-sample the desktop")
    }

    func testResizingScreenshotKeepsCapturedImageWithoutRequestingAnotherCapture() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1000, height: 800), styleMask: .borderless, backing: .buffered, defer: false)
        let controller = CaptureController()
        defer { controller.cancel() }
        let image = try makeImage()
        let original = CGRect(x: 100, y: 100, width: 400, height: 300)
        controller.beginEditing(image, selection: original, in: window)
        let start = window.convertPoint(fromScreen: CGPoint(x: original.maxX, y: original.maxY))
        let end = window.convertPoint(fromScreen: CGPoint(x: original.maxX + 80, y: original.maxY + 60))

        controller.mouseDown(at: start)
        controller.mouseDragged(to: end)
        controller.mouseUp(at: end)

        XCTAssertEqual(controller.selection, CGRect(x: 100, y: 100, width: 480, height: 360))
        XCTAssertTrue(controller.image === image)
        XCTAssertNil(controller.captureRequestID)
    }

    func testToolbarStaysCompactAndOnlyExpandsForAnActiveTool() throws {
        _ = NSApplication.shared
        let toolbar = CaptureToolbar(onAction: { _ in }, onColorChange: { _ in }, onMosaicChange: { _ in })
        let compactSize = toolbar.fittingSize
        XCTAssertGreaterThan(compactSize.width, 300)
        XCTAssertLessThanOrEqual(compactSize.width, 620)
        XCTAssertEqual(compactSize.height, 48)
        let undo = try XCTUnwrap(button(in: toolbar, tip: "撤销"))
        let redo = try XCTUnwrap(button(in: toolbar, tip: "重做"))
        XCTAssertFalse(undo.isEnabled)
        XCTAssertFalse(redo.isEnabled)
        for tip in ["矩形", "椭圆", "箭头", "高亮", "马赛克", "文字", "撤销", "重做", "保存", "钉住", "取消截图", "完成并复制"] {
            XCTAssertNotNil(try XCTUnwrap(button(in: toolbar, tip: tip)).image, "Missing toolbar icon: \(tip)")
        }

        toolbar.update(tool: .rect, canUndo: true, canRedo: false, color: .black, mosaicBlock: 18)
        XCTAssertGreaterThan(toolbar.fittingSize.height, compactSize.height)
        XCTAssertLessThanOrEqual(toolbar.fittingSize.height, 84)
        XCTAssertTrue(undo.isEnabled)
        XCTAssertFalse(redo.isEnabled)

        toolbar.update(tool: nil, canUndo: false, canRedo: true, color: .black, mosaicBlock: 18)
        XCTAssertEqual(toolbar.fittingSize, compactSize)
        XCTAssertTrue(redo.isEnabled)
    }

    func testToolbarCompletionAndToolButtonsInvokeTheirActions() throws {
        _ = NSApplication.shared
        var didCopy = false
        var didChooseMosaic = false
        let toolbar = CaptureToolbar(onAction: { action in
            switch action {
            case .copy: didCopy = true
            case .tool(.mosaic): didChooseMosaic = true
            default: break
            }
        }, onColorChange: { _ in }, onMosaicChange: { _ in })

        try XCTUnwrap(button(in: toolbar, tip: "完成并复制")).performClick(nil)
        try XCTUnwrap(button(in: toolbar, tip: "马赛克")).performClick(nil)
        XCTAssertTrue(didCopy)
        XCTAssertTrue(didChooseMosaic)
    }

    private func button(in view: NSView, tip: String) -> NSButton? {
        if let button = view as? NSButton, button.toolTip == tip { return button }
        return view.subviews.lazy.compactMap { self.button(in: $0, tip: tip) }.first
    }

    private func makeImage() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 40, height: 30, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.red.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 20, height: 30))
        context.setFillColor(NSColor.blue.cgColor)
        context.fill(CGRect(x: 20, y: 0, width: 20, height: 30))
        return try XCTUnwrap(context.makeImage())
    }
}
