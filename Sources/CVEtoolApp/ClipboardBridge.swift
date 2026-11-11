import AppKit
import CVEtoolCore
import Foundation

enum PasteboardMarker {
    static let type = NSPasteboard.PasteboardType("com.hershel.cvetool.own")
}

final class ClipboardWatcher {
    static let shared = ClipboardWatcher()
    private var timer: Timer?
    private var lastChangeCount = -1

    func start(store: HistoryStore) {
        lastChangeCount = NSPasteboard.general.changeCount
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
            self?.poll(store: store)
        }
    }

    func poll(store: HistoryStore) {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        if pasteboard.string(forType: PasteboardMarker.type) == "1" { return }
        let payload = Self.read(pasteboard)
        let result: AddResult
        switch payload {
        case .ignore:
            return
        case .text(let text):
            result = store.addText(kind: .text, text: text, limitBytes: SettingsStore.shared.capacityBytes)
        case .link(let text):
            result = store.addText(kind: .link, text: text, limitBytes: SettingsStore.shared.capacityBytes)
        case .color(let text):
            result = store.addText(kind: .color, text: text, limitBytes: SettingsStore.shared.capacityBytes)
        case .image(let data):
            result = store.addImage(data, isScreenshot: false, limitBytes: SettingsStore.shared.capacityBytes)
        }
        if case .rejectedOversized = result {
            Toast.show("这一张超过容量上限，没有放入历史")
        }
        NotificationCenter.default.post(name: .historyDidChange, object: nil)
    }

    static func read(_ pasteboard: NSPasteboard) -> ClipboardPayload {
        let types = pasteboard.types ?? []
        let image = pngData(from: pasteboard)
        let text = pasteboard.string(forType: .string)
        let fileOnly = types.contains(.fileURL) && text == nil && image == nil
        if types.contains(NSPasteboard.PasteboardType("com.apple.cocoa.pasteboard.color")),
           let color = NSColor(from: pasteboard) {
            let converted = color.usingColorSpace(.sRGB) ?? color
            let hex = String(format: "#%02X%02X%02X", Int(converted.redComponent * 255), Int(converted.greenComponent * 255), Int(converted.blueComponent * 255))
            if image == nil { return .color(hex) }
        }
        return ClipboardClassifier.classify(text: text, imagePNG: image, fileOnly: fileOnly)
    }

    static func pngData(from pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png), !png.isEmpty { return png }
        if let tiff = pasteboard.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            return png
        }
        return nil
    }

    static func writeOwn(_ body: (NSPasteboard) -> Void) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        body(pasteboard)
        pasteboard.setString("1", forType: PasteboardMarker.type)
    }
}

enum PasteService {
    static func paste(_ item: HistoryItem, store: HistoryStore, to app: NSRunningApplication?) {
        ClipboardWatcher.writeOwn { pasteboard in
            switch item.kind {
            case .text, .link, .color:
                pasteboard.setString(item.text ?? "", forType: .string)
            case .image, .screenshot:
                if let data = store.imageData(for: item) {
                    pasteboard.setData(data, forType: .png)
                }
            }
        }
        guard PermissionService.accessibilityGranted else {
            PermissionService.alertAndOpen(message: "辅助功能未授权，内容已复制。授权后可以自动粘贴。", pane: "Accessibility")
            return
        }
        let target = app
        target?.activate(options: [.activateIgnoringOtherApps])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            postCommandV()
        }
    }

    static func copyImage(_ data: Data) {
        ClipboardWatcher.writeOwn { pasteboard in
            pasteboard.setData(data, forType: .png)
        }
    }

    private static func postCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        down?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        up?.flags = .maskCommand
        up?.post(tap: .cghidEventTap)
    }
}
