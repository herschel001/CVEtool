import AppKit
import CVEtoolCore
import ScreenCaptureKit

enum CaptureMode {
    case region, window, fullscreen
}

final class CaptureController: NSObject, NSWindowDelegate {
    static let shared = CaptureController()
    private(set) var isActive = false
    private var canvasWindow: NSWindow?
    private var canvas: CaptureCanvas?
    private var mode: CaptureMode = .region
    private var phase: Phase = .selecting
    private(set) var selection = CGRect.zero
    private(set) var image: CGImage?
    private(set) var captureRequestID: UUID?
    private var strokes: [AnnotationStroke] = []
    private var undone: [AnnotationStroke] = []
    private var tool: AnnotationStroke.Kind?
    private var anchor = CGPoint.zero
    private var originalSelection = CGRect.zero
    private var interaction: Interaction = .none
    private var mosaicPoints: [CGPoint] = []
    private var highlightedWindow = CGRect.null
    private var strokeColor = CaptureToolbar.palette[1].1
    private var mosaicBlock: CGFloat = 18
    private var textField: NSTextField?
    private var keyMonitor: Any?
    private var toolbar: CaptureToolbar?

    private enum Phase { case selecting, annotating }
    private enum Interaction: Equatable {
        case none, creating, moving, resizing(Handle), drawing
    }
    private enum Handle: Equatable { case n, s, e, w, nw, ne, sw, se }

    func start(_ mode: CaptureMode) {
        HistoryPanelController.shared.hide()
        guard PermissionService.screenRecordingGranted else {
            PermissionService.promptScreenRecording()
            return
        }
        self.mode = mode
        captureRequestID = nil
        strokes = []
        undone = []
        tool = nil
        image = nil
        selection = .zero
        highlightedWindow = .null
        toolbar?.removeFromSuperview()
        toolbar = nil
        phase = .selecting
        isActive = true
        let screen = screenUnderMouse()
        if mode == .fullscreen {
            selection = screen.frame
            captureSelection()
            return
        }
        showCanvas(on: screen)
    }

    func cancel() {
        captureRequestID = nil
        textField?.removeFromSuperview()
        textField = nil
        canvasWindow?.orderOut(nil)
        canvasWindow = nil
        canvas = nil
        image = nil
        isActive = false
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        NSApp.deactivate()
    }

    private func showCanvas(on screen: NSScreen) {
        let window = KeyableCaptureWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.ignoresMouseEvents = false
        window.isReleasedWhenClosed = false
        let view = CaptureCanvas(owner: self)
        window.contentView = view
        window.setFrame(screen.frame, display: true)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        canvasWindow = window
        canvas = view
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.isActive else { return event }
                if event.keyCode == 53 {
                    if self.textField != nil {
                        self.commitText()
                        return nil
                    }
                    self.cancel()
                    return nil
                }
                return event
            }
        }
        view.needsDisplay = true
    }

    func mouseDown(at windowPoint: CGPoint) {
        guard let window = canvasWindow else { return }
        let screenPoint = window.convertPoint(toScreen: windowPoint)
        if phase == .annotating {
            if let handle = hitHandle(windowPoint) {
                interaction = .resizing(handle)
                anchor = screenPoint
                originalSelection = selection
                return
            }
            if tool == nil, selection.contains(screenPoint) {
                interaction = .moving
                anchor = screenPoint
                originalSelection = selection
                return
            }
            if let tool {
                interaction = .drawing
                let local = localPoint(screenPoint)
                anchor = local
                mosaicPoints = tool == .mosaic ? [local] : []
                if tool == .text {
                    beginText(at: local)
                    interaction = .none
                }
            }
            return
        }
        if mode == .window {
            guard let hit = windowUnder(screenPoint), hit.width > 40, hit.height > 40 else { return }
            selection = hit
            captureSelection()
            return
        }
        interaction = .creating
        anchor = screenPoint
        selection = CGRect(origin: screenPoint, size: .zero)
        canvas?.needsDisplay = true
    }

    func mouseDragged(to windowPoint: CGPoint) {
        guard let window = canvasWindow else { return }
        let screenPoint = window.convertPoint(toScreen: windowPoint)
        switch interaction {
        case .creating:
            selection = rect(from: anchor, to: screenPoint)
        case .moving:
            let dx = screenPoint.x - anchor.x
            let dy = screenPoint.y - anchor.y
            selection = originalSelection.offsetBy(dx: dx, dy: dy)
        case .resizing(let handle):
            let delta = CGPoint(x: screenPoint.x - anchor.x, y: screenPoint.y - anchor.y)
            selection = resized(originalSelection, handle: handle, by: delta)
        case .drawing:
            let local = localPoint(screenPoint)
            if tool == .mosaic {
                mosaicPoints.append(local)
            } else if let tool, tool != .text {
                replaceTentative(styledStroke(kind: tool, start: anchor, end: local))
            }
        case .none:
            if mode == .window, phase == .selecting {
                highlightedWindow = windowUnder(screenPoint) ?? .null
            }
        }
        canvas?.needsDisplay = true
    }

    func mouseUp(at windowPoint: CGPoint) {
        defer {
            interaction = .none
            mosaicPoints = []
            canvas?.needsDisplay = true
        }
        guard let window = canvasWindow else { return }
        let screenPoint = window.convertPoint(toScreen: windowPoint)
        if interaction == .drawing, tool == .mosaic, !mosaicPoints.isEmpty {
            strokes.append(styledStroke(kind: .mosaic, start: mosaicPoints[0], end: mosaicPoints.last ?? mosaicPoints[0], points: mosaicPoints))
            undone.removeAll()
            return
        }
        if interaction == .creating {
            selection = rect(from: anchor, to: screenPoint)
            guard selection.width >= 8, selection.height >= 8 else {
                selection = .zero
                return
            }
            captureSelection()
        }
    }

    fileprivate func mouseMoved(to windowPoint: CGPoint) {
        _ = windowPoint
    }

    fileprivate func chooseTool(_ tool: AnnotationStroke.Kind?) {
        commitText()
        self.tool = self.tool == tool ? nil : tool
        canvas?.needsDisplay = true
    }

    fileprivate func undoStroke() {
        guard let last = strokes.popLast() else { return }
        undone.append(last)
        canvas?.needsDisplay = true
    }

    fileprivate func redoStroke() {
        guard let last = undone.popLast() else { return }
        strokes.append(last)
        canvas?.needsDisplay = true
    }

    fileprivate func draw(_ dirty: NSRect, in view: NSView) {
        NSColor.black.withAlphaComponent(phase == .annotating ? 0.28 : 0.38).setFill()
        dirty.fill()
        guard let window = canvasWindow else { return }
        let hole = window.convertFromScreen(selection)
        if phase == .selecting {
            guard interaction == .creating, selection.width > 2, selection.height > 2 else { return }
            NSColor.clear.setFill()
            hole.fill(using: .copy)
            NSColor.black.withAlphaComponent(0.55).setStroke()
            let path = NSBezierPath(rect: hole)
            path.lineWidth = 1
            path.stroke()
            drawBadge("\(Int(selection.width)) × \(Int(selection.height))", at: hole)
            return
        }
        if let image {
            NSGraphicsContext.current?.saveGraphicsState()
            NSBezierPath(rect: hole).addClip()
            NSImage(cgImage: image, size: hole.size).draw(in: hole)
            drawStrokes(in: hole)
            NSGraphicsContext.current?.restoreGraphicsState()
        }
        for handle in [Handle.n, .s, .e, .w, .nw, .ne, .sw, .se] {
            NSColor.white.setFill()
            NSColor.black.withAlphaComponent(0.45).setStroke()
            let mark = NSBezierPath(ovalIn: handleRect(handle, around: hole))
            mark.fill()
            mark.stroke()
        }
        drawBadge("\(Int(selection.width)) × \(Int(selection.height))", at: hole)
    }

    fileprivate func placeToolbar(in view: NSView) {
        guard phase == .annotating, let window = canvasWindow else {
            toolbar?.removeFromSuperview()
            return
        }
        let toolbar = self.toolbar ?? makeToolbar()
        self.toolbar = toolbar
        if toolbar.superview == nil { view.addSubview(toolbar) }
        toolbar.update(tool: tool, canUndo: !strokes.isEmpty, canRedo: !undone.isEmpty, color: strokeColor, mosaicBlock: mosaicBlock)
        let size = toolbar.fittingSize
        let screen = window.screen?.frame ?? window.frame
        let frame: CGRect
        if mode == .fullscreen {
            frame = ScreenGeometry.fullscreenToolbarFrame(toolbarSize: size, screen: screen)
        } else {
            frame = ScreenGeometry.toolbarFrame(selection: selection, toolbarSize: size, screen: screen)
        }
        toolbar.frame = window.convertFromScreen(frame)
    }

    private func captureSelection() {
        let rect = selection
        let captureRect = ScreenGeometry.captureRect(fromAppKitSelection: rect, primaryHeight: primaryScreenHeight)
        let requestID = UUID()
        captureRequestID = requestID
        canvasWindow?.orderOut(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self, self.isActive, self.captureRequestID == requestID else { return }
            guard #available(macOS 15.2, *) else {
                Toast.show("需要 macOS 15.2 或更新版本才能截图")
                self.cancel()
                return
            }
            SCScreenshotManager.captureImage(in: captureRect) { image, error in
                DispatchQueue.main.async {
                    guard self.isActive, self.captureRequestID == requestID else { return }
                    self.captureRequestID = nil
                    guard let image else {
                        Toast.show(error?.localizedDescription ?? "没有截到画面")
                        self.cancel()
                        return
                    }
                    let screen = self.screenContaining(rect) ?? self.screenUnderMouse()
                    if self.canvasWindow == nil { self.showCanvas(on: screen) }
                    guard let window = self.canvasWindow else { self.cancel(); return }
                    self.beginEditing(image, selection: rect, in: window)
                    window.setFrame(screen.frame, display: true)
                    window.makeKeyAndOrderFront(nil)
                    self.canvas?.needsDisplay = true
                    if let canvas = self.canvas { self.placeToolbar(in: canvas) }
                }
            }
        }
    }

    func beginEditing(_ image: CGImage, selection: CGRect, in window: NSWindow) {
        self.image = image
        self.selection = selection
        canvasWindow = window
        phase = .annotating
        isActive = true
    }

    private func finish(copy: Bool, save: Bool, pin: Bool) {
        guard let image else { cancel(); return }
        commitText()
        let rendered = AnnotationRenderer.render(base: image, strokes: strokes, viewSize: selection.size) ?? image
        guard let data = pngData(rendered) else {
            Toast.show("没有保存")
            return
        }
        let store = HistoryPanelController.shared.store
        if save {
            canvasWindow?.orderOut(nil)
            NSApp.activate(ignoringOtherApps: true)
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.png]
            panel.nameFieldStringValue = "截图 \(Self.filenameStamp()).png"
            panel.canCreateDirectories = true
            let response = panel.runModal()
            if response == .OK, let url = panel.url {
                do {
                    try data.write(to: url, options: .atomic)
                    record(data, store: store, allowRejectToast: true)
                    cancel()
                } catch {
                    canvasWindow?.orderFrontRegardless()
                    Toast.show("没有保存")
                }
            } else {
                canvasWindow?.orderFrontRegardless()
            }
            return
        }
        if copy { PasteService.copyImage(data) }
        record(data, store: store, allowRejectToast: true)
        if pin { PinWindowController.shared.show(image: NSImage(data: data) ?? NSImage()) }
        cancel()
    }

    private func record(_ data: Data, store: HistoryStore?, allowRejectToast: Bool) {
        guard let store else { return }
        let result = store.addImage(data, isScreenshot: true, limitBytes: SettingsStore.shared.capacityBytes)
        if case .rejectedOversized = result, allowRejectToast {
            Toast.show("这一张超过容量上限，没有放入历史")
        }
        NotificationCenter.default.post(name: .historyDidChange, object: nil)
    }

    private func beginText(at local: CGPoint) {
        commitText()
        guard let canvas, let window = canvasWindow else { return }
        let field = NSTextField(frame: NSRect(x: selection.minX - window.frame.minX + local.x, y: selection.minY - window.frame.minY + local.y, width: 220, height: 28))
        field.placeholderString = "输入文字，按 Esc 结束"
        field.font = .systemFont(ofSize: 16)
        field.isBezeled = true
        field.isEditable = true
        field.isSelectable = true
        field.drawsBackground = true
        field.backgroundColor = .white
        field.textColor = strokeColor
        canvas.addSubview(field)
        window.makeKey()
        window.makeFirstResponder(field)
        textField = field
    }

    private func commitText() {
        guard let field = textField else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty, let window = canvasWindow {
            let screenPoint = window.convertPoint(toScreen: field.frame.origin)
            strokes.append(styledStroke(kind: .text, start: localPoint(screenPoint), end: localPoint(screenPoint), text: text))
            undone.removeAll()
        }
        field.removeFromSuperview()
        textField = nil
    }

    private func makeToolbar() -> CaptureToolbar {
        CaptureToolbar(
            onAction: { [weak self] action in
                guard let self else { return }
                switch action {
                case .tool(let kind): self.chooseTool(kind)
                case .undo: self.undoStroke()
                case .redo: self.redoStroke()
                case .copy: self.finish(copy: true, save: false, pin: false)
                case .save: self.finish(copy: false, save: true, pin: false)
                case .pin: self.finish(copy: false, save: false, pin: true)
                case .discard: self.cancel()
                }
            },
            onColorChange: { [weak self] color in
                self?.strokeColor = color
                self?.canvas?.needsDisplay = true
            },
            onMosaicChange: { [weak self] size in
                self?.mosaicBlock = size
            }
        )
    }

    private func drawStrokes(in hole: NSRect) {
        let transform = NSAffineTransform()
        transform.translateX(by: hole.minX, yBy: hole.minY)
        NSGraphicsContext.current?.saveGraphicsState()
        transform.concat()
        for stroke in strokes + tentativeStroke() where stroke.isVisible {
            let color = NSColor(srgbRed: stroke.red, green: stroke.green, blue: stroke.blue, alpha: 1)
            color.setStroke()
            switch stroke.kind {
            case .arrow:
                let path = NSBezierPath()
                path.lineWidth = 2.5
                path.move(to: stroke.start)
                path.line(to: stroke.end)
                path.stroke()
                let angle = atan2(stroke.end.y - stroke.start.y, stroke.end.x - stroke.start.x)
                let head: CGFloat = 12
                let left = CGPoint(x: stroke.end.x - head * cos(angle - .pi / 6), y: stroke.end.y - head * sin(angle - .pi / 6))
                let right = CGPoint(x: stroke.end.x - head * cos(angle + .pi / 6), y: stroke.end.y - head * sin(angle + .pi / 6))
                let headPath = NSBezierPath()
                headPath.move(to: left)
                headPath.line(to: stroke.end)
                headPath.line(to: right)
                headPath.lineWidth = 2.5
                headPath.stroke()
            case .rect:
                let path = NSBezierPath(rect: rect(from: stroke.start, to: stroke.end))
                path.lineWidth = 2.5
                path.stroke()
            case .ellipse:
                let path = NSBezierPath(ovalIn: rect(from: stroke.start, to: stroke.end))
                path.lineWidth = 2.5
                path.stroke()
            case .highlight:
                color.withAlphaComponent(0.45).setFill()
                NSBezierPath(rect: rect(from: stroke.start, to: stroke.end)).fill()
            case .text:
                let text = NSAttributedString(string: stroke.text, attributes: [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: color])
                text.draw(at: stroke.start)
            case .mosaic:
                let radius = CGFloat(stroke.mosaicBlock)
                NSColor.systemGray.withAlphaComponent(0.28).setFill()
                for point in stroke.mosaicPoints {
                    NSBezierPath(rect: NSRect(x: point.x - radius / 2, y: point.y - radius / 2, width: radius, height: radius)).fill()
                }
            }
        }
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    private func tentativeStroke() -> [AnnotationStroke] {
        guard interaction == .drawing, tool == .mosaic, !mosaicPoints.isEmpty else { return [] }
        return [styledStroke(kind: .mosaic, start: mosaicPoints[0], end: mosaicPoints.last ?? mosaicPoints[0], points: mosaicPoints)]
    }

    private func replaceTentative(_ stroke: AnnotationStroke) {
        if strokes.last?.kind == stroke.kind, interaction == .drawing, strokes.last?.start == anchor {
            strokes[strokes.count - 1] = stroke
        } else if stroke.isVisible {
            strokes.append(stroke)
            undone.removeAll()
        }
    }

    private func styledStroke(kind: AnnotationStroke.Kind, start: CGPoint, end: CGPoint, text: String = "", points: [CGPoint] = []) -> AnnotationStroke {
        let rgb = strokeColor.usingColorSpace(.sRGB) ?? strokeColor
        return AnnotationStroke(
            kind: kind,
            start: start,
            end: end,
            text: text,
            mosaicPoints: points,
            red: Double(rgb.redComponent),
            green: Double(rgb.greenComponent),
            blue: Double(rgb.blueComponent),
            mosaicBlock: Double(mosaicBlock)
        )
    }

    private func hitHandle(_ windowPoint: CGPoint) -> Handle? {
        guard let window = canvasWindow, selection.width > 8 else { return nil }
        let hole = window.convertFromScreen(selection)
        let order: [Handle] = [.nw, .ne, .sw, .se, .n, .s, .e, .w]
        for handle in order where handleRect(handle, around: hole).insetBy(dx: -6, dy: -6).contains(windowPoint) {
            return handle
        }
        return nil
    }

    private func handleRect(_ handle: Handle, around hole: NSRect) -> NSRect {
        let size: CGFloat = 10
        let origin: CGPoint
        switch handle {
        case .nw: origin = NSPoint(x: hole.minX - size / 2, y: hole.maxY - size / 2)
        case .ne: origin = NSPoint(x: hole.maxX - size / 2, y: hole.maxY - size / 2)
        case .sw: origin = NSPoint(x: hole.minX - size / 2, y: hole.minY - size / 2)
        case .se: origin = NSPoint(x: hole.maxX - size / 2, y: hole.minY - size / 2)
        case .n: origin = NSPoint(x: hole.midX - size / 2, y: hole.maxY - size / 2)
        case .s: origin = NSPoint(x: hole.midX - size / 2, y: hole.minY - size / 2)
        case .e: origin = NSPoint(x: hole.maxX - size / 2, y: hole.midY - size / 2)
        case .w: origin = NSPoint(x: hole.minX - size / 2, y: hole.midY - size / 2)
        }
        return NSRect(origin: origin, size: NSSize(width: size, height: size))
    }

    private func resized(_ original: CGRect, handle: Handle, by delta: CGPoint) -> CGRect {
        var rect = original
        let minimum: CGFloat = 24
        switch handle {
        case .e, .ne, .se:
            rect.size.width = max(minimum, original.width + delta.x)
        case .w, .nw, .sw:
            let width = max(minimum, original.width - delta.x)
            rect.origin.x = original.maxX - width
            rect.size.width = width
        default:
            break
        }
        switch handle {
        case .n, .ne, .nw:
            rect.size.height = max(minimum, original.height + delta.y)
            rect.origin.y = original.origin.y
        case .s, .se, .sw:
            let height = max(minimum, original.height - delta.y)
            rect.origin.y = original.minY + (original.height - height)
            rect.size.height = height
        default:
            break
        }
        return rect
    }

    private func windowUnder(_ screenPoint: CGPoint) -> CGRect? {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        let primaryHeight = primaryScreenHeight
        let cgPoint = CGPoint(x: screenPoint.x, y: primaryHeight - screenPoint.y)
        let candidates: [WindowCandidate] = info.compactMap { item in
            guard let bounds = item[kCGWindowBounds as String] as? [String: CGFloat] else { return nil }
            return WindowCandidate(
                owner: item[kCGWindowOwnerName as String] as? String ?? "",
                layer: item[kCGWindowLayer as String] as? Int ?? 0,
                alpha: item[kCGWindowAlpha as String] as? Double ?? 1,
                bounds: CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0, width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0),
                ownerPID: (item[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? -1
            )
        }
        guard let hit = WindowPicker.hit(candidates: candidates, cgPoint: cgPoint, ownPID: ProcessInfo.processInfo.processIdentifier) else { return nil }
        return ScreenGeometry.appKitRect(fromCGWindowBounds: hit, primaryHeight: primaryHeight)
    }

    private func localPoint(_ screenPoint: CGPoint) -> CGPoint {
        CGPoint(x: screenPoint.x - selection.minX, y: screenPoint.y - selection.minY)
    }

    private var primaryScreenHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    private func rect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    private func drawBadge(_ text: String, at hole: NSRect) {
        let badge = NSAttributedString(string: text, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white])
        let size = badge.size()
        let bg = NSRect(x: hole.minX, y: hole.maxY + 6, width: size.width + 10, height: size.height + 4)
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: bg, xRadius: 4, yRadius: 4).fill()
        badge.draw(at: NSPoint(x: bg.minX + 5, y: bg.minY + 2))
    }

    private func pngData(_ image: CGImage) -> Data? {
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .png, properties: [:])
    }

    private func screenUnderMouse() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func screenContaining(_ rect: CGRect) -> NSScreen? {
        NSScreen.screens.max { a, b in
            a.frame.intersection(rect).width * a.frame.intersection(rect).height < b.frame.intersection(rect).width * b.frame.intersection(rect).height
        }
    }

    private static func filenameStamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter.string(from: Date())
    }
}

private extension NSWindow {
    func convertFromScreen(_ rect: CGRect) -> NSRect {
        let origin = convertPoint(fromScreen: rect.origin)
        return NSRect(origin: origin, size: rect.size)
    }
}

final class KeyableCaptureWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class DraggableImageView: NSImageView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        var origin = window.frame.origin
        origin.x += event.deltaX
        origin.y -= event.deltaY
        window.setFrameOrigin(origin)
    }
}

final class CaptureCanvas: NSView {
    weak var owner: CaptureController?
    init(owner: CaptureController) {
        self.owner = owner
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        owner?.draw(dirtyRect, in: self)
        owner?.placeToolbar(in: self)
    }
    override func mouseDown(with event: NSEvent) { owner?.mouseDown(at: event.locationInWindow) }
    override func mouseDragged(with event: NSEvent) { owner?.mouseDragged(to: event.locationInWindow) }
    override func mouseUp(with event: NSEvent) { owner?.mouseUp(at: event.locationInWindow) }
    override func mouseMoved(with event: NSEvent) { owner?.mouseMoved(to: event.locationInWindow) }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }
}

final class PinWindowController {
    static let shared = PinWindowController()
    private var window: NSPanel?

    func show(image: NSImage) {
        window?.close()
        let size = NSSize(width: min(520, image.size.width), height: min(360, image.size.height))
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let imageView = DraggableImageView(frame: NSRect(origin: .zero, size: size))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 10
        imageView.layer?.masksToBounds = true
        let close = NSButton(frame: NSRect(x: size.width - 28, y: size.height - 28, width: 22, height: 22))
        close.title = "×"
        close.bezelStyle = .circular
        close.target = self
        close.action = #selector(closePin)
        panel.contentView = imageView
        imageView.addSubview(close)
        if let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2))
        }
        panel.orderFrontRegardless()
        window = panel
    }

    @objc func closePin() {
        window?.close()
        window = nil
    }
}
