import AppKit
import Carbon
import CVEtoolCore
import Foundation
import ServiceManagement

enum AppPaths {
    static var supportDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["CVETOOL_SUPPORT_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("CVEtool", isDirectory: true)
    }
}

struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var characters: String

    static let region = Shortcut(keyCode: 18, modifiers: UInt32(cmdKey | shiftKey), characters: "1")
    static let window = Shortcut(keyCode: 19, modifiers: UInt32(cmdKey | shiftKey), characters: "2")
    static let fullscreen = Shortcut(keyCode: 20, modifiers: UInt32(cmdKey | shiftKey), characters: "3")
    static let history = Shortcut(keyCode: 9, modifiers: UInt32(cmdKey | shiftKey), characters: "v")

    var modifierFlags: NSEvent.ModifierFlags {
        var flags = NSEvent.ModifierFlags()
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        return flags
    }

    var display: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        text += characters.count == 1 ? characters.uppercased() : characters
        return text
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var value: UInt32 = 0
        if flags.contains(.command) { value |= UInt32(cmdKey) }
        if flags.contains(.shift) { value |= UInt32(shiftKey) }
        if flags.contains(.option) { value |= UInt32(optionKey) }
        if flags.contains(.control) { value |= UInt32(controlKey) }
        return value
    }
}

enum ShortcutKind: String, CaseIterable {
    case region, window, fullscreen, history

    var title: String {
        switch self {
        case .region: return "区域截图"
        case .window: return "窗口截图"
        case .fullscreen: return "全屏截图"
        case .history: return "打开历史"
        }
    }

    var hotkeyID: UInt32 {
        switch self {
        case .region: return 1
        case .window: return 2
        case .fullscreen: return 3
        case .history: return 4
        }
    }
}

final class SettingsStore {
    static let shared = SettingsStore()
    private let defaults = UserDefaults.standard

    private init() {}

    var capacityMB: Int {
        get {
            let value = defaults.integer(forKey: "capacityMB")
            return CapacityPolicy.choicesMB.contains(value) ? value : 200
        }
        set {
            let value = CapacityPolicy.choicesMB.contains(newValue) ? newValue : 200
            defaults.set(value, forKey: "capacityMB")
            NotificationCenter.default.post(name: .capacityDidChange, object: nil)
        }
    }

    var capacityBytes: Int64 { CapacityPolicy.bytes(fromMegabytes: capacityMB) }

    var launchAtLogin: Bool {
        get { defaults.object(forKey: "launchAtLogin") as? Bool ?? true }
        set {
            defaults.set(newValue, forKey: "launchAtLogin")
            LaunchAtLogin.apply(newValue)
        }
    }

    func shortcut(for kind: ShortcutKind) -> Shortcut {
        guard let data = defaults.data(forKey: "shortcut.\(kind.rawValue)"),
              let value = try? JSONDecoder().decode(Shortcut.self, from: data) else {
            return Self.defaultShortcut(kind)
        }
        return value
    }

    func setShortcut(_ shortcut: Shortcut, for kind: ShortcutKind) {
        if let data = try? JSONEncoder().encode(shortcut) {
            defaults.set(data, forKey: "shortcut.\(kind.rawValue)")
        }
        NotificationCenter.default.post(name: .shortcutsDidChange, object: nil)
    }

    static func defaultShortcut(_ kind: ShortcutKind) -> Shortcut {
        switch kind {
        case .region: return .region
        case .window: return .window
        case .fullscreen: return .fullscreen
        case .history: return .history
        }
    }

    static func isReservedBySystem(_ shortcut: Shortcut) -> Bool {
        var unmanaged: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&unmanaged) == noErr, let array = unmanaged?.takeRetainedValue() as? [NSDictionary] else { return false }
        for item in array {
            let enabled = (item[kHISymbolicHotKeyEnabled] as? Bool) ?? ((item[kHISymbolicHotKeyEnabled] as? NSNumber)?.boolValue ?? false)
            guard enabled else { continue }
            let code = (item[kHISymbolicHotKeyCode] as? NSNumber)?.uint32Value
            let mods = (item[kHISymbolicHotKeyModifiers] as? NSNumber)?.uint32Value
            if code == shortcut.keyCode && mods == shortcut.modifiers { return true }
        }
        return false
    }
}

enum LaunchAtLogin {
    static func apply(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("开机启动设置失败: \(error.localizedDescription)")
        }
    }
}

extension Notification.Name {
    static let capacityDidChange = Notification.Name("CVEtool.capacityDidChange")
    static let shortcutsDidChange = Notification.Name("CVEtool.shortcutsDidChange")
    static let historyDidChange = Notification.Name("CVEtool.historyDidChange")
}

enum Toast {
    private static var panel: NSPanel?

    static func show(_ message: String) {
        DispatchQueue.main.async {
            panel?.orderOut(nil)
            let label = NSTextField(labelWithString: message)
            label.font = .systemFont(ofSize: 13)
            label.textColor = .labelColor
            label.translatesAutoresizingMaskIntoConstraints = false
            let content = NSView()
            content.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
                label.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
                label.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
                label.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),
            ])
            let width = min(420, max(180, label.intrinsicContentSize.width + 28))
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: 36), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isFloatingPanel = true
            panel.level = .statusBar
            panel.backgroundColor = .windowBackgroundColor
            panel.isOpaque = false
            panel.hasShadow = true
            panel.collectionBehavior = [.canJoinAllSpaces, .transient]
            panel.contentView = content
            if let screen = NSScreen.main {
                panel.setFrameOrigin(NSPoint(x: screen.frame.midX - width / 2, y: screen.frame.midY))
            }
            panel.orderFrontRegardless()
            self.panel = panel
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { [weak panel] in
                panel?.orderOut(nil)
            }
        }
    }
}

enum PermissionService {
    static var screenRecordingGranted: Bool { CGPreflightScreenCaptureAccess() }

    static var accessibilityGranted: Bool { AXIsProcessTrusted() }

    static func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
    }

    static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func promptScreenRecording() {
        if screenRecordingGranted { return }
        NSApp.activate(ignoringOtherApps: true)
        if CGRequestScreenCaptureAccess() { return }
        openPrivacy("ScreenCapture")
    }

    static func alertAndOpen(message: String, pane: String) {
        if pane == "ScreenCapture" {
            promptScreenRecording()
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        requestAccessibility()
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = "点「去授权」打开系统设置里的辅助功能。如果开关已经打开仍不能自动粘贴，退出并重新打开本应用。"
        alert.addButton(withTitle: "去授权")
        alert.addButton(withTitle: "退出并重新打开")
        alert.addButton(withTitle: "取消")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            openPrivacy(pane)
        case .alertSecondButtonReturn:
            relaunch()
        default:
            break
        }
    }

    static func relaunch() {
        let bundle = Bundle.main.bundleURL
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", bundle.path]
        try? task.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            NSApp.terminate(nil)
        }
    }

    static func openPrivacy(_ pane: String) {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_\(pane)",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_\(pane)",
        ]
        for raw in urls {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}

final class HotkeyCenter {
    static let shared = HotkeyCenter()
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: () -> Void] = [:]
    private var installed = false

    func start() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else { return status }
            let center = Unmanaged<HotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { center.handlers[hotKeyID.id]?() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
    }

    @discardableResult
    func register(id: UInt32, shortcut: Shortcut, handler: @escaping () -> Void) -> Bool {
        if let existing = refs[id] {
            UnregisterEventHotKey(existing)
            refs[id] = nil
        }
        handlers[id] = handler
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4356_544C), id: id)
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        refs[id] = ref
        return true
    }

    func unregister(id: UInt32) {
        if let existing = refs[id] {
            UnregisterEventHotKey(existing)
            refs[id] = nil
        }
        handlers[id] = nil
    }
}
