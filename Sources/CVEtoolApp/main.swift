import AppKit
import CVEtoolCore
import Foundation

let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.setActivationPolicy(.accessory)
application.run()

final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?
    private var statusItem: NSStatusItem?
    private var menuItems: [ShortcutKind: NSMenuItem] = [:]
    let store = HistoryStore(directory: AppPaths.supportDirectory)

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        HistoryPanelController.shared.store = store
        configureStatusItem()
        HotkeyCenter.shared.start()
        registerHotkeys()
        ClipboardWatcher.shared.start(store: store)
        if ProcessInfo.processInfo.environment["CVETOOL_OPEN_HISTORY"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                HistoryPanelController.shared.show()
            }
        }
        if SettingsStore.shared.launchAtLogin {
            LaunchAtLogin.apply(true)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(registerHotkeys), name: .shortcutsDidChange, object: nil)
        store.shrink(to: SettingsStore.shared.capacityBytes)
    }

    func applicationWillTerminate(_ notification: Notification) {
        PinWindowController.shared.closeForQuit()
    }

    @objc func registerHotkeys() {
        for kind in ShortcutKind.allCases {
            let shortcut = SettingsStore.shared.shortcut(for: kind)
            HotkeyCenter.shared.register(id: kind.hotkeyID, shortcut: shortcut) { [weak self] in
                self?.perform(kind)
            }
            menuItems[kind]?.keyEquivalent = shortcut.characters.lowercased()
            menuItems[kind]?.keyEquivalentModifierMask = shortcut.modifierFlags
        }
    }

    func perform(_ kind: ShortcutKind) {
        switch kind {
        case .region: CaptureController.shared.start(.region)
        case .window: CaptureController.shared.start(.window)
        case .fullscreen: CaptureController.shared.start(.fullscreen)
        case .history:
            if CaptureController.shared.isActive { return }
            HistoryPanelController.shared.toggle()
        }
    }

    private func configureStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.statusItem = statusItem
        if let button = statusItem.button {
            button.image = AppIcon.statusImage()
            button.setAccessibilityLabel("截图剪贴板")
        }
        let menu = NSMenu()
        for kind in [ShortcutKind.region, .window, .fullscreen] {
            let item = NSMenuItem(title: kind.title, action: #selector(menuAction(_:)), keyEquivalent: "")
            item.target = self
            item.identifier = NSUserInterfaceItemIdentifier(kind.rawValue)
            menu.addItem(item)
            menuItems[kind] = item
        }
        menu.addItem(.separator())
        let history = NSMenuItem(title: "打开历史", action: #selector(menuAction(_:)), keyEquivalent: "")
        history.target = self
        history.identifier = NSUserInterfaceItemIdentifier(ShortcutKind.history.rawValue)
        menu.addItem(history)
        menuItems[.history] = history
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
        registerHotkeys()
    }

    @objc private func menuAction(_ sender: NSMenuItem) {
        guard let raw = sender.identifier?.rawValue, let kind = ShortcutKind(rawValue: raw) else { return }
        perform(kind)
    }

    @objc private func openSettings() { SettingsWindowController.shared.show() }
    @objc private func quit() { NSApp.terminate(nil) }
}

extension PinWindowController {
    func closeForQuit() { closePin() }
}
